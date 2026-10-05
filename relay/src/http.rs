//! Optional clearnet HTTP ingress for the relay.
//!
//! This is a small HTTP/1.1 adapter around the existing RelayCore. It does not define a second
//! mailbox protocol: POST /v1/relay carries the exact same versioned JSON request line used by
//! the onion/TCP relay and returns the exact same versioned JSON response.
//!
//! TLS is terminated by a reverse proxy (Caddy/nginx) on public port 443. This listener should bind
//! to loopback in production, for example 127.0.0.1:9080. It is disabled unless
//! NIGHTDROP_RELAY_HTTP_BIND is set by the operator.
//!
//! Unlike the onion ingress, this path is not anonymous: the reverse proxy / hosting network can
//! observe source IP addresses and timing. The relay still receives only opaque E2E-encrypted blobs.

use std::io::{self, BufRead, BufReader, Read, Write};
use std::net::{SocketAddr, TcpListener, TcpStream};
use std::sync::atomic::{AtomicUsize, Ordering};
use std::sync::Arc;
use std::thread;
use std::time::Duration;

use nightdrop::relay_client::RelayCore;

const MAX_HEADER_BYTES: usize = 32 * 1024;
const MAX_CONNECTIONS: usize = 256;
const IO_TIMEOUT: Duration = Duration::from_secs(15);

struct ConnGuard(Arc<AtomicUsize>);

impl Drop for ConnGuard {
    fn drop(&mut self) {
        self.0.fetch_sub(1, Ordering::Relaxed);
    }
}

/// Bind the HTTP ingress and serve it on a background thread.
///
/// Returns the actual bound address (useful when tests bind port 0). The caller should normally use
/// a loopback address and put a TLS reverse proxy in front of it.
pub fn spawn(bind: &str, core: Arc<RelayCore>) -> io::Result<SocketAddr> {
    let listener = TcpListener::bind(bind)?;
    let local = listener.local_addr()?;
    let active = Arc::new(AtomicUsize::new(0));

    thread::Builder::new()
        .name("nightdrop-http-relay".into())
        .spawn(move || {
            for stream in listener.incoming() {
                let Ok(stream) = stream else {
                    continue;
                };

                if active.fetch_add(1, Ordering::Relaxed) >= MAX_CONNECTIONS {
                    active.fetch_sub(1, Ordering::Relaxed);
                    let _ = reject_busy(stream);
                    continue;
                }

                let core = Arc::clone(&core);
                let guard = ConnGuard(Arc::clone(&active));
                let _ = thread::Builder::new()
                    .name("nightdrop-http-client".into())
                    .spawn(move || {
                        let _guard = guard;
                        let _ = serve_one(stream, &core);
                    });
            }
        })?;

    Ok(local)
}

fn reject_busy(mut stream: TcpStream) -> io::Result<()> {
    stream.set_write_timeout(Some(IO_TIMEOUT))?;
    write_response(
        &mut stream,
        503,
        "Service Unavailable",
        "text/plain; charset=utf-8",
        b"busy\n",
    )
}

fn serve_one(stream: TcpStream, core: &RelayCore) -> io::Result<()> {
    stream.set_read_timeout(Some(IO_TIMEOUT))?;
    stream.set_write_timeout(Some(IO_TIMEOUT))?;

    let mut reader = BufReader::new(stream);
    let request_line = read_header_line_capped(&mut reader, MAX_HEADER_BYTES)?;
    if request_line.is_empty() {
        return Ok(());
    }

    let mut parts = request_line
        .trim_end_matches(['\r', '\n'])
        .split_whitespace();
    let method = parts.next().unwrap_or("");
    let path = parts.next().unwrap_or("");
    let version = parts.next().unwrap_or("");
    if parts.next().is_some() || !version.starts_with("HTTP/1.") {
        return write_reader_response(
            reader,
            400,
            "Bad Request",
            "text/plain; charset=utf-8",
            b"bad request\n",
        );
    }

    let mut header_bytes = request_line.len();
    let mut content_length: Option<usize> = None;
    let mut transfer_encoding = false;

    loop {
        let line = read_header_line_capped(
            &mut reader,
            MAX_HEADER_BYTES.saturating_sub(header_bytes),
        )?;
        header_bytes = header_bytes.saturating_add(line.len());
        if line == "\r\n" || line == "\n" || line.is_empty() {
            break;
        }

        let Some((name, value)) = line.split_once(':') else {
            return write_reader_response(
                reader,
                400,
                "Bad Request",
                "text/plain; charset=utf-8",
                b"bad header\n",
            );
        };
        let name = name.trim();
        let value = value.trim();
        if name.eq_ignore_ascii_case("content-length") {
            let parsed = value.parse::<usize>().map_err(|_| {
                io::Error::new(io::ErrorKind::InvalidData, "invalid content-length")
            })?;
            if content_length.replace(parsed).is_some() {
                return write_reader_response(
                    reader,
                    400,
                    "Bad Request",
                    "text/plain; charset=utf-8",
                    b"duplicate content-length\n",
                );
            }
        } else if name.eq_ignore_ascii_case("transfer-encoding") {
            transfer_encoding = true;
        }
    }

    match (method, path) {
        ("GET", "/healthz") => {
            write_reader_response(reader, 200, "OK", "text/plain; charset=utf-8", b"ok\n")
        }
        ("POST", "/v1/relay") => {
            if transfer_encoding {
                return write_reader_response(
                    reader,
                    400,
                    "Bad Request",
                    "text/plain; charset=utf-8",
                    b"transfer-encoding unsupported\n",
                );
            }
            let Some(len) = content_length else {
                return write_reader_response(
                    reader,
                    411,
                    "Length Required",
                    "text/plain; charset=utf-8",
                    b"content-length required\n",
                );
            };
            if len > core.max_line_bytes() {
                return write_reader_response(
                    reader,
                    413,
                    "Payload Too Large",
                    "text/plain; charset=utf-8",
                    b"payload too large\n",
                );
            }

            let mut body = vec![0u8; len];
            reader.read_exact(&mut body)?;
            let body = match std::str::from_utf8(&body) {
                Ok(s) => s.trim_end_matches(['\r', '\n']),
                Err(_) => {
                    return write_reader_response(
                        reader,
                        400,
                        "Bad Request",
                        "text/plain; charset=utf-8",
                        b"body must be utf-8 json\n",
                    )
                }
            };

            // One protocol definition only: RelayCore parses, version-checks, enforces limits,
            // mutates the mailbox store, and serializes the response exactly as it does over Tor.
            let response = core.handle_line(body);
            write_reader_response(reader, 200, "OK", "application/json", response.as_bytes())
        }
        ("POST", _) | ("GET", _) => write_reader_response(
            reader,
            404,
            "Not Found",
            "text/plain; charset=utf-8",
            b"not found\n",
        ),
        _ => write_reader_response(
            reader,
            405,
            "Method Not Allowed",
            "text/plain; charset=utf-8",
            b"method not allowed\n",
        ),
    }
}

/// Read one HTTP header/request line without ever buffering beyond `max`.
///
/// `BufRead::read_line` only tells us the size *after* it has appended the whole line, which
/// lets an unauthenticated clearnet client force an arbitrarily large allocation before the
/// 32 KiB header cap is checked. Read from `fill_buf` in bounded slices instead, exactly like
/// the relay protocol's own capped line reader.
fn read_header_line_capped<R: BufRead>(reader: &mut R, max: usize) -> io::Result<String> {
    if max == 0 {
        return Err(io::Error::new(
            io::ErrorKind::InvalidData,
            "headers too large",
        ));
    }

    let mut out = Vec::new();
    loop {
        let (consume, done) = {
            let chunk = reader.fill_buf()?;
            if chunk.is_empty() {
                (0usize, true)
            } else if let Some(i) = chunk.iter().position(|&b| b == b'\n') {
                let take = i + 1; // keep CRLF/LF so the blank-line test stays trivial
                if out.len().saturating_add(take) > max {
                    return Err(io::Error::new(
                        io::ErrorKind::InvalidData,
                        "headers too large",
                    ));
                }
                out.extend_from_slice(&chunk[..take]);
                (take, true)
            } else {
                if out.len().saturating_add(chunk.len()) > max {
                    return Err(io::Error::new(
                        io::ErrorKind::InvalidData,
                        "headers too large",
                    ));
                }
                out.extend_from_slice(chunk);
                (chunk.len(), false)
            }
        };
        reader.consume(consume);

        if done {
            if out.is_empty() && consume == 0 {
                return Ok(String::new());
            }
            return String::from_utf8(out)
                .map_err(|_| io::Error::new(io::ErrorKind::InvalidData, "headers must be utf-8"));
        }
    }
}

fn write_reader_response(
    mut reader: BufReader<TcpStream>,
    status: u16,
    reason: &str,
    content_type: &str,
    body: &[u8],
) -> io::Result<()> {
    write_response(reader.get_mut(), status, reason, content_type, body)
}

fn write_response(
    stream: &mut TcpStream,
    status: u16,
    reason: &str,
    content_type: &str,
    body: &[u8],
) -> io::Result<()> {
    write!(
        stream,
        "HTTP/1.1 {status} {reason}\r\nContent-Type: {content_type}\r\nContent-Length: {}\r\nCache-Control: no-store\r\nX-Content-Type-Options: nosniff\r\nConnection: close\r\n\r\n",
        body.len()
    )?;
    stream.write_all(body)?;
    stream.flush()
}

#[cfg(test)]
mod tests {
    use super::*;
    use nightdrop::relay_client::{parse_response_line, request_line, Request};
    use std::net::TcpStream;

    fn http_post(addr: SocketAddr, body: &str) -> String {
        let mut stream = TcpStream::connect(addr).unwrap();
        write!(
            stream,
            "POST /v1/relay HTTP/1.1\r\nHost: localhost\r\nContent-Type: application/json\r\nContent-Length: {}\r\nConnection: close\r\n\r\n{}",
            body.len(),
            body
        )
        .unwrap();
        stream.flush().unwrap();

        let mut response = String::new();
        stream.read_to_string(&mut response).unwrap();
        response
    }

    fn body(response: &str) -> &str {
        response.split_once("\r\n\r\n").unwrap().1
    }

    #[test]
    fn header_line_limit_is_enforced_before_unbounded_buffering() {
        use std::io::Cursor;

        let mut reader = Cursor::new(vec![b'a'; 64]);
        let err = read_header_line_capped(&mut reader, 32).unwrap_err();
        assert_eq!(err.kind(), io::ErrorKind::InvalidData);
    }

    #[test]
    fn post_then_take_reuses_the_existing_relay_protocol() {
        let core = Arc::new(RelayCore::new(None));
        let addr = spawn("127.0.0.1:0", core).unwrap();

        let post = request_line(&Request::Post {
            handle: "mailbox-a".into(),
            blob: "aGVsbG8=".into(),
            ttl_secs: 60,
        })
        .unwrap();
        let response = http_post(addr, &post);
        assert!(response.starts_with("HTTP/1.1 200 OK\r\n"));
        let parsed = parse_response_line(body(&response)).unwrap();
        assert!(parsed.ok);
        assert!(parsed.msg_id.is_some());

        let take = request_line(&Request::Take {
            handle: "mailbox-a".into(),
        })
        .unwrap();
        let response = http_post(addr, &take);
        let parsed = parse_response_line(body(&response)).unwrap();
        assert!(parsed.ok);
        assert_eq!(parsed.blobs, vec!["aGVsbG8=".to_string()]);
    }

    #[test]
    fn oversized_body_is_rejected_before_json_parsing() {
        let limits = nightdrop::relay_client::RelayLimits {
            max_line_bytes: 32,
            ..Default::default()
        };
        let core = Arc::new(RelayCore::with_limits(None, limits));
        let addr = spawn("127.0.0.1:0", core).unwrap();

        let response = http_post(addr, &"x".repeat(33));
        assert!(response.starts_with("HTTP/1.1 413 Payload Too Large\r\n"));
    }

    #[test]
    fn health_endpoint_contains_no_user_data() {
        let core = Arc::new(RelayCore::new(None));
        let addr = spawn("127.0.0.1:0", core).unwrap();
        let mut stream = TcpStream::connect(addr).unwrap();
        stream
            .write_all(b"GET /healthz HTTP/1.1\r\nHost: localhost\r\nConnection: close\r\n\r\n")
            .unwrap();
        let mut response = String::new();
        stream.read_to_string(&mut response).unwrap();
        assert!(response.starts_with("HTTP/1.1 200 OK\r\n"));
        assert_eq!(body(&response), "ok\n");
    }
}
