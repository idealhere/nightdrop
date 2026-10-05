# HTTPS relay deployment (reliability-first fork)

This guide exposes the **same Night Drop RelayCore/store** through two network paths:

- HTTPS on public TCP/443 for the normal fast path.
- The relay's existing v3 onion service for Tor/WebTunnel fallback.

These are two endpoints for one logical relay. Do **not** point the HTTPS hostname at one relay
process and the onion address at another process/store; destructive mailbox operations would then
be inconsistent across failover.

## 1. Prerequisites

- One Linux VPS.
- A DNS name such as `relay.example.com` pointing to that VPS.
- Public TCP 80/443 allowed to the VPS (80 is used by Caddy for ACME when applicable).
- Night Drop relay installed from this repository.

The Rust HTTP adapter itself must remain loopback-only. Public TLS is terminated by Caddy.

## 2. Install / update the relay

Use the existing installer:

```bash
sudo relay/deploy/install-relay.sh
```

The committed systemd unit sets:

```
NIGHTDROP_RELAY_HTTP_BIND=127.0.0.1:9080
```

Check both the process and its local health endpoint:

```bash
sudo systemctl status nightdrop-relay --no-pager
curl --fail --silent http://127.0.0.1:9080/healthz
```

Expected body:

```
ok
```

The relay still publishes its onion address exactly as before. Keep that address: the Android build
uses it only as the lazy privacy/censorship fallback.

## 3. Put TLS in front

Install Caddy using the official package for the server distribution, then copy
`relay/deploy/Caddyfile.https.example` to `/etc/caddy/Caddyfile` and replace
`relay.example.com` with the real hostname.

The important part is:

```caddyfile
relay.example.com {
    reverse_proxy 127.0.0.1:9080

    header {
        -Server
        Cache-Control "no-store"
        X-Content-Type-Options "nosniff"
    }
}
```

Reload Caddy:

```bash
sudo systemctl reload caddy
sudo systemctl status caddy --no-pager
```

Do **not** enable request-body logging. The body is opaque ciphertext, but retaining mailbox
operations provides no operational benefit and creates avoidable metadata.

## 4. Verify public TLS and the mailbox protocol

First:

```bash
curl --fail https://relay.example.com/healthz
```

Then run the repository smoke test from any machine with Python 3:

```bash
python3 scripts/check_https_relay.py https://relay.example.com/v1/relay
```

A passing probe proves:

- the certificate validates;
- public TCP/443 reaches the relay;
- `POST /v1/relay` accepts the existing versioned relay protocol;
- an opaque blob can be posted and destructively drained;
- the mailbox is empty after `take`.

The smoke probe uses a random throwaway mailbox and no real identity/contact keys.

## 5. Build Android HTTPS-first + lazy Tor fallback

Both values must describe the **same logical relay/store**:

```bash
NIGHTDROP_HTTPS_RELAY=https://relay.example.com/v1/relay \
NIGHTDROP_RELAY=abcdefghijklmnopqrstuvwxyz234567abcdefghijklmnopqrstuvwxyz2345.onion \
scripts/install-android-app.sh --release
```

Normal startup uses HTTPS only and does not pay Tor bootstrap cost. If repeated delivery proves the
fast path is unavailable, or a short-code join fails over HTTPS, the app reopens the same persisted
identity on Tor and upgrades the relay to:

```
https://relay.example.com/v1/relay|abcdefghijklmnopqrstuvwxyz234567abcdefghijklmnopqrstuvwxyz2345.onion
```

The HTTPS endpoint is still tried first after the switch. The onion endpoint is the fallback.

## 6. Failure test before calling it production-ready

On a test device with an established chat:

1. Confirm messages work over normal HTTPS.
2. Temporarily block the HTTPS hostname/443 for the device (or stop Caddy, leaving the relay/Tor
   service running).
3. Attempt delivery enough times to trigger the conservative liveness threshold, or attempt a
   short-code join.
4. Confirm the app bootstraps Tor/WebTunnel and the chat identity/session survives without
   re-pairing.
5. Restore HTTPS and confirm later relay operations prefer HTTPS again.

For Russia testing, repeat on at least one fixed-line provider and multiple mobile carriers.
Record only route success/failure and latency, never message plaintext.

## Privacy boundary

HTTPS keeps message contents end-to-end encrypted, but it is **not anonymous**. The TLS terminator,
hosting provider, and network can observe client IP addresses, timing, and traffic sizes. The onion
fallback is the path that hides the client IP from the relay host.
