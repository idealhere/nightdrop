#!/usr/bin/env python3
"""End-to-end smoke test for a public Night Drop HTTPS relay.

Usage:
    python3 scripts/check_https_relay.py https://relay.example.com/v1/relay

The probe creates one random mailbox, posts one opaque test blob, drains it, and verifies the
returned bytes. It exercises public TLS + the exact relay v1 JSON protocol without touching any
real identity, contact, key, or chat.
"""

from __future__ import annotations

import base64
import json
import os
import sys
import urllib.error
import urllib.parse
import urllib.request


def fail(message: str) -> "NoReturn":
    print(f"FAIL: {message}", file=sys.stderr)
    raise SystemExit(1)


def request_json(endpoint: str, req: dict) -> dict:
    body = json.dumps({"v": 1, "req": req}, separators=(",", ":")).encode()
    http_req = urllib.request.Request(
        endpoint,
        data=body,
        method="POST",
        headers={
            "Content-Type": "application/json",
            "Accept": "application/json",
            "Cache-Control": "no-store",
            "User-Agent": "nightdrop-relay-smoke/1",
        },
    )
    try:
        with urllib.request.urlopen(http_req, timeout=15) as response:
            if response.status != 200:
                fail(f"POST returned HTTP {response.status}")
            raw = response.read()
    except urllib.error.URLError as exc:
        fail(f"POST failed: {exc}")

    try:
        line = json.loads(raw.decode("utf-8"))
    except Exception as exc:
        fail(f"invalid JSON response: {exc}")
    if line.get("v") != 1:
        fail(f"unexpected relay protocol version: {line.get('v')!r}")
    resp = line.get("resp")
    if not isinstance(resp, dict):
        fail("response has no resp object")
    if not resp.get("ok"):
        fail(f"relay returned error: {resp.get('error')!r}")
    return resp


def main() -> None:
    if len(sys.argv) != 2:
        fail("usage: check_https_relay.py https://relay.example.com/v1/relay")
    endpoint = sys.argv[1].strip()
    parsed = urllib.parse.urlparse(endpoint)
    if parsed.scheme != "https" or not parsed.hostname:
        fail("endpoint must be an https:// URL")
    if parsed.query or parsed.fragment or parsed.username or parsed.password:
        fail("endpoint must not contain credentials, query, or fragment")

    health = urllib.parse.urlunparse(
        (parsed.scheme, parsed.netloc, "/healthz", "", "", "")
    )
    try:
        with urllib.request.urlopen(health, timeout=10) as response:
            body = response.read(128)
            if response.status != 200 or body != b"ok\n":
                fail(f"health check unexpected response: HTTP {response.status} {body!r}")
    except urllib.error.URLError as exc:
        fail(f"health check failed: {exc}")
    print(f"OK: TLS + health endpoint: {health}")

    handle = "smoke:" + os.urandom(16).hex()
    payload = b"nightdrop-https-relay-smoke-" + os.urandom(12)
    blob = base64.b64encode(payload).decode("ascii")

    posted = request_json(
        endpoint,
        {"op": "post", "handle": handle, "blob": blob, "ttl_secs": 60},
    )
    if not posted.get("msg_id") or not posted.get("delete_token"):
        fail("post succeeded but receipt fields are missing")
    print("OK: opaque blob accepted")

    taken = request_json(endpoint, {"op": "take", "handle": handle})
    blobs = taken.get("blobs", [])
    if blobs != [blob]:
        fail(f"take returned unexpected blobs: {blobs!r}")
    print("OK: same opaque blob drained")

    empty = request_json(endpoint, {"op": "take", "handle": handle})
    if empty.get("blobs", []) != []:
        fail("mailbox was not destructive-drained")
    print("OK: mailbox is empty after destructive take")
    print("PASS: public HTTPS relay is protocol-ready")


if __name__ == "__main__":
    main()
