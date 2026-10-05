# HTTPS-primary transport for the Night Drop fork

Status: design baseline for implementation branch `feature/https-primary-transport`.

## Goal

Keep Night Drop's end-to-end encryption, pairing, ratchet, local encrypted storage, and existing
Tor/WebTunnel path, while adding a fast clearnet delivery path suitable for normal everyday use
between countries such as the United States and Russia.

The application should choose the transport automatically. Users should not need to understand
Tor, bridges, relay addresses, or WebTunnel.

## Security boundary

Message contents MUST remain end-to-end encrypted before they enter any transport.

The HTTPS relay is intentionally **not anonymous**. It can see the connecting IP address, request
timing, ciphertext size, and the mailbox handle used for a request. It must never receive message
plaintext, identity private keys, ratchet keys, recovery passwords, or unencrypted attachments.

Do not silently describe the HTTPS path as anonymous. UI copy should say "Encrypted connection";
"Anonymous connection" is reserved for the Tor path.

The existing Tor/WebTunnel path remains available as the privacy/censorship fallback.

## V1 routing order

1. HTTPS relay A over TLS 1.3 / port 443.
2. HTTPS relay B over TLS 1.3 / port 443.
3. Tor through WebTunnel when direct Tor is blocked.
4. Direct Tor.

A failed path should not destroy or mutate the E2E frame. The same sealed frame is retried through
the next eligible delivery path.

Backoff must prevent rapid retry loops:
- immediate failover for a connection error;
- 5 s, 15 s, 60 s retry delays for the failed route;
- reset a route after a successful health check.

## V1 topology

The first implementation uses relay delivery for HTTPS rather than exposing a phone as an inbound
public HTTPS server.

    sender
      |
      | TLS 1.3 / HTTPS 443
      v
    HTTPS relay  ---- opaque E2E blob ----> temporary mailbox
                                            |
                                            | TLS 1.3 / HTTPS 443
                                            v
                                         recipient

This keeps mobile NAT/firewall handling simple and makes Android background delivery practical.

Direct P2P over Tor remains unchanged and can still be used when Tor is the selected path.

## Relay protocol

Do not invent a second message format. Reuse the existing `relay_client::Request` and
`relay_client::Response` semantics:

- post
- peek
- fetch
- take
- take_many
- recall
- get_directory

The HTTPS adapter serializes the existing versioned request as JSON and sends it in an HTTP request.
The server feeds the request to the existing `RelayCore`; storage and TTL behaviour stay shared
between Tor and HTTPS.

Initial API:

- `POST /v1/relay`
- request body: existing versioned relay JSON
- response body: existing versioned relay JSON
- `Content-Type: application/json`
- hard request-size limit equal to the current relay line limit
- no cookies
- no account/session token
- no analytics
- no plaintext logging
- no request-body logging

A WebSocket endpoint may be added later for lower-latency long polling, but V1 should first prove
the simpler request/response path.

## Client abstraction

Add a clearnet HTTPS relay dialer without changing the cryptographic core.

The existing node already accepts a `RelayDialer` abstraction:
a function taking one versioned relay request and returning one response. The new path should
implement the same abstraction, so mailbox derivation, envelope encryption, deduplication,
recall, and TTL logic remain unchanged.

The transport selector owns a list of relay routes with health state:

```
Route {
    kind: Https | TorWebTunnel | Tor,
    endpoint: String,
    health: Healthy | CoolingDown | Unknown,
    last_error: Option<...>,
}
```

No route may downgrade encryption. "HTTPS primary" changes network metadata exposure only; E2E
message encryption is mandatory on every route.

## Pairing

Short-code pairing needs a rendezvous mailbox reachable by both devices before they know each
other. V1 uses the public HTTPS relay first and falls back to the existing Tor relay.

QR pairing remains local/pre-authorized and does not need a server-side identity.

## Mobile background behaviour

Android should prefer the low-cost HTTPS mailbox check while the app is backgrounded. If the HTTPS
route is unavailable, the foreground/active app may bring up WebTunnel/Tor and drain the same
mailbox there.

Do not continuously bootstrap Tor in the background merely to prove connectivity when HTTPS is
healthy.

## Server placement

Run at least two independent HTTPS relays in different providers/regions. Do not make the client
depend on one hostname, IP, ASN, or cloud provider.

For the first deployment:
- relay A: United States
- relay B: Western/Northern Europe

Both relays should use the same application protocol but separate state. Multi-relay fan-out and
deduplication already present in Night Drop should be reused where possible.

## Logging policy

Production HTTPS relay logs must not include:
- request bodies;
- ciphertext;
- mailbox handles in full;
- IP addresses in application logs;
- user-agent strings tied to mailbox operations.

Infrastructure access logs should be disabled or minimized. This does not make the HTTPS path
anonymous: the hosting/network provider can still observe source IPs.

## Abuse controls

The clearnet relay is easier to reach and abuse than an onion-only relay. Before public launch:
- retain the existing per-blob, per-mailbox and total storage caps;
- add per-IP connection/request rate limits at the edge;
- bound body size before JSON parsing;
- cap concurrent requests;
- keep the existing maximum TTL;
- reject malformed protocol versions early.

Rate limiting must never depend on a permanent user account.

## Implementation phases

### Phase 1 — protocol reuse
- expose the relay request dispatcher through an HTTP handler;
- add an HTTPS `RelayDialer` client;
- integration test: post -> fetch through HTTP with opaque bytes;
- confirm the same `RelayCore` serves both TCP/onion and HTTP paths.

### Phase 2 — route manager
- add ordered relay routes;
- health/cooldown state;
- automatic HTTPS A -> HTTPS B -> WebTunnel/Tor fallback;
- deterministic tests with injected failing dialers.

### Phase 3 — Android
- wire route state to Flutter;
- show only user-facing connection states;
- background mailbox check over HTTPS;
- no manual bridge UI required for the normal case.

### Phase 4 — deployment
- two relay VPS instances;
- TLS certificates and automatic renewal;
- no CDN requirement for V1;
- health endpoint that contains no user data;
- load and failure testing.

### Phase 5 — censorship testing
Test from real Russian networks (mobile and fixed-line), not only simulated blocking:
- normal HTTPS path;
- alternate relay;
- WebTunnel fallback;
- Tor fallback.

Record only transport success/failure and latency; never capture message plaintext.

## Acceptance criteria for V1

- Two clean Android installs can pair and exchange messages with Tor disabled when HTTPS is
  reachable.
- Killing relay A causes automatic delivery through relay B.
- Blocking both HTTPS relays causes fallback to WebTunnel/Tor without re-pairing.
- Switching paths does not change contact identity or reset the Double Ratchet session.
- Server never needs an E2E private key.
- Offline messages expire under the same existing TTL rules.
- Existing Tor-only operation still works.
- Existing core crypto tests remain unchanged and passing.
