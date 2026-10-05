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

    /// There is deliberately no directly reachable peer address.
    fn published(&self) -> bool {
        false
    }
}

#[cfg(test)]
mod tests {
    use super::*;

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
