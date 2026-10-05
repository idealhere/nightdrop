//! Relay-only transport for the reliability-first fork.
//!
//! This transport intentionally has no peer-to-peer socket. Every direct peer send fails fast, so
//! Node's existing delivery logic immediately falls back to its configured relay mailbox. The E2E
//! frame is still produced by the same crypto/session code before this layer sees it.
//!
//! It is useful when starting the app on a network where Tor is unavailable or slow: short-code
//! pairing and message delivery can proceed through the HTTPS relay without waiting for an onion
//! service to bootstrap.
//!
//! Privacy: this transport provides NO anonymity. The relay path decides what network metadata is
//! exposed (direct HTTPS reveals source IP/timing; a Tor relay dialer does not).

use std::sync::mpsc::{channel, Receiver};
use std::sync::Mutex;

use crate::transport::{Address, Transport};
use crate::Result;

/// A transport endpoint with no direct P2P listener.
///
/// The address is a protocol marker carried inside encrypted pairing/control data. Peers must never
/// attempt to interpret it as a host name; send always fails locally and the caller falls back to
/// the relay mailbox.
pub struct RelayOnlyTransport {
    inbound: Mutex<Receiver<(Address, Vec<u8>)>>,
}

impl RelayOnlyTransport {
    pub fn new() -> Self {
        let (_tx, rx) = channel();
        Self {
            inbound: Mutex::new(rx),
        }
    }
}

impl Default for RelayOnlyTransport {
    fn default() -> Self {
        Self::new()
    }
}

impl Transport for RelayOnlyTransport {
    fn address(&self) -> Address {
        "relay-only".to_string()
    }

    fn send(&self, _peer: &str, _frame: &[u8]) -> Result<()> {
        anyhow::bail!("direct peer path unavailable in relay-only mode")
    }

    fn try_recv(&self) -> Option<(Address, Vec<u8>)> {
        self.inbound.lock().unwrap().try_recv().ok()
    }

    /// Delivery still performs network I/O through the configured RelayClient, so keep it off the
    /// UI/core-lock hot path exactly like Tor.
    fn is_synchronous(&self) -> bool {
        false
    }

    fn is_relay_only(&self) -> bool {
        true
    }

    /// Extra relays advertised by contacts may also be clearnet HTTPS relays. Build the same
    /// direct-TLS dialer used by the primary so Night Drop's existing multi-relay fan-out works
    /// before Tor is bootstrapped.
    ///
    /// A malformed https:// address returns an erroring dialer rather than `None`: `None` tells
    /// the node to fall back to a plain TCP RelayClient, which must never receive an HTTPS URL.
    fn relay_dialer(&self, addr: &str) -> Option<crate::relay_client::RelayDialer> {
        if !addr.starts_with("https://") {
            return None;
        }
        Some(match crate::relay_client::https::https_relay_dialer(addr) {
            Ok(dialer) => dialer,
            Err(error) => {
                let message = format!("invalid HTTPS relay endpoint: {error}");
                std::sync::Arc::new(move |_| Err(anyhow::anyhow!(message.clone())))
            }
        })
    }

    /// There is deliberately no directly reachable peer address.
    fn published(&self) -> bool {
        false
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[cfg(feature = "https-relay")]
    #[test]
    fn https_extra_relays_get_a_tls_dialer_not_plain_tcp_fallback() {
        let t = RelayOnlyTransport::new();
        assert!(t.relay_dialer("https://relay.example/v1/relay").is_some());
        assert!(t.relay_dialer("relay.example:443").is_none());

        // Malformed HTTPS still returns a dialer; executing it fails locally instead of handing
        // the URL to the system TCP resolver.
        let bad = t.relay_dialer("https://").unwrap();
        assert!(bad("request").is_err());
    }

    #[test]
    fn direct_delivery_fails_without_touching_the_network() {
        let t = RelayOnlyTransport::new();
        assert_eq!(t.address(), "relay-only");
        assert!(t.send("anything", b"sealed frame").is_err());
        assert!(t.try_recv().is_none());
        assert!(!t.published());
        assert!(!t.is_synchronous());
    }
}
