//! Ordered relay failover with per-route cooldown.
//!
//! The caller supplies already-built RelayDialers (HTTPS A, HTTPS B, WebTunnel/Tor, ...). This
//! module knows nothing about crypto or message formats: it retries the exact same serialized relay
//! request on the next route. That is important for Night Drop because the E2E envelope must be
//! sealed once and remain byte-identical across failover.

use std::sync::{Arc, Mutex};
use std::time::{Duration, Instant};

use super::RelayDialer;
use crate::Result;

const BACKOFFS: [Duration; 3] = [
    Duration::from_secs(5),
    Duration::from_secs(15),
    Duration::from_secs(60),
];

/// One named route in priority order. Names are diagnostics only; do not put identities or other
/// user data in them.
#[derive(Clone)]
pub struct FailoverRoute {
    pub name: String,
    pub dialer: RelayDialer,
}

impl FailoverRoute {
    pub fn new(name: impl Into<String>, dialer: RelayDialer) -> Self {
        Self {
            name: name.into(),
            dialer,
        }
    }
}

struct RouteState {
    route: FailoverRoute,
    consecutive_failures: usize,
    retry_after: Option<Instant>,
}

impl RouteState {
    fn ready(&self, now: Instant) -> bool {
        self.retry_after.is_none_or(|at| at <= now)
    }

    fn mark_success(&mut self) {
        self.consecutive_failures = 0;
        self.retry_after = None;
    }

    fn mark_failure(&mut self, now: Instant) {
        let index = self
            .consecutive_failures
            .min(BACKOFFS.len().saturating_sub(1));
        self.consecutive_failures = self.consecutive_failures.saturating_add(1);
        self.retry_after = Some(now + BACKOFFS[index]);
    }
}

/// Build a RelayDialer that tries routes in priority order and cools down a route after failures.
///
/// Routing policy:
/// - first failure: 5 s cooldown;
/// - second consecutive failure: 15 s;
/// - third and later: 60 s;
/// - one successful round trip resets that route immediately.
///
/// If every route is cooling down, the route whose cooldown expires first is tried so the client
/// never becomes artificially offline solely because of its own backoff timer.
pub fn failover_dialer(routes: Vec<FailoverRoute>) -> RelayDialer {
    let state = Arc::new(Mutex::new(
        routes
            .into_iter()
            .map(|route| RouteState {
                route,
                consecutive_failures: 0,
                retry_after: None,
            })
            .collect::<Vec<_>>(),
    ));

    Arc::new(move |line: &str| -> Result<String> {
        let now = Instant::now();

        // Snapshot only indices + Arc dialers; never hold the route-state lock across network I/O.
        let attempts: Vec<(usize, String, RelayDialer)> = {
            let routes = state.lock().unwrap_or_else(|e| e.into_inner());
            if routes.is_empty() {
                return Err(anyhow::anyhow!("no relay routes configured"));
            }

            let mut ready: Vec<usize> = routes
                .iter()
                .enumerate()
                .filter_map(|(i, r)| r.ready(now).then_some(i))
                .collect();

            if ready.is_empty() {
                // All routes are cooling. Probe the one closest to becoming eligible rather than
                // refusing the request without touching the network.
                let i = routes
                    .iter()
                    .enumerate()
                    .min_by_key(|(_, r)| r.retry_after)
                    .map(|(i, _)| i)
                    .unwrap_or(0);
                ready.push(i);
            }

            ready
                .into_iter()
                .map(|i| (i, routes[i].route.name.clone(), Arc::clone(&routes[i].route.dialer)))
                .collect()
        };

        let mut errors = Vec::new();
        for (index, name, dial) in attempts {
            match dial(line) {
                Ok(response) => {
                    let mut routes = state.lock().unwrap_or_else(|e| e.into_inner());
                    if let Some(route) = routes.get_mut(index) {
                        route.mark_success();
                    }
                    return Ok(response);
                }
                Err(error) => {
                    let mut routes = state.lock().unwrap_or_else(|e| e.into_inner());
                    if let Some(route) = routes.get_mut(index) {
                        route.mark_failure(Instant::now());
                    }
                    errors.push(format!("{name}: {error}"));
                }
            }
        }

        Err(anyhow::anyhow!(
            "all eligible relay routes failed: {}",
            errors.join("; ")
        ))
    })
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::atomic::{AtomicUsize, Ordering};

    #[test]
    fn falls_through_without_changing_the_request() {
        let seen = Arc::new(Mutex::new(Vec::<String>::new()));
        let a_seen = Arc::clone(&seen);
        let a: RelayDialer = Arc::new(move |line| {
            a_seen.lock().unwrap().push(format!("a:{line}"));
            Err(anyhow::anyhow!("down"))
        });
        let b_seen = Arc::clone(&seen);
        let b: RelayDialer = Arc::new(move |line| {
            b_seen.lock().unwrap().push(format!("b:{line}"));
            Ok("response".into())
        });

        let dial = failover_dialer(vec![
            FailoverRoute::new("https-a", a),
            FailoverRoute::new("https-b", b),
        ]);
        let request = "{\"v\":1,\"req\":{\"op\":\"peek\",\"handle\":\"x\"}}\n";
        assert_eq!(dial(request).unwrap(), "response");

        let seen = seen.lock().unwrap();
        assert_eq!(seen.as_slice(), &[format!("a:{request}"), format!("b:{request}")]);
    }

    #[test]
    fn failed_primary_cools_down_so_next_call_uses_backup_first() {
        let a_calls = Arc::new(AtomicUsize::new(0));
        let a_count = Arc::clone(&a_calls);
        let a: RelayDialer = Arc::new(move |_| {
            a_count.fetch_add(1, Ordering::Relaxed);
            Err(anyhow::anyhow!("down"))
        });

        let b_calls = Arc::new(AtomicUsize::new(0));
        let b_count = Arc::clone(&b_calls);
        let b: RelayDialer = Arc::new(move |_| {
            b_count.fetch_add(1, Ordering::Relaxed);
            Ok("ok".into())
        });

        let dial = failover_dialer(vec![
            FailoverRoute::new("https-a", a),
            FailoverRoute::new("https-b", b),
        ]);

        assert_eq!(dial("one").unwrap(), "ok");
        assert_eq!(dial("two").unwrap(), "ok");
        assert_eq!(a_calls.load(Ordering::Relaxed), 1);
        assert_eq!(b_calls.load(Ordering::Relaxed), 2);
    }

    #[test]
    fn no_routes_is_an_error() {
        let dial = failover_dialer(Vec::new());
        let err = dial("request").unwrap_err().to_string();
        assert!(err.contains("no relay routes"));
    }

    #[test]
    fn reports_each_attempt_when_all_routes_fail() {
        let fail = |why: &'static str| -> RelayDialer {
            Arc::new(move |_| Err(anyhow::anyhow!(why)))
        };
        let dial = failover_dialer(vec![
            FailoverRoute::new("https-a", fail("a down")),
            FailoverRoute::new("https-b", fail("b down")),
        ]);
        let err = dial("request").unwrap_err().to_string();
        assert!(err.contains("https-a: a down"));
        assert!(err.contains("https-b: b down"));
    }
}
