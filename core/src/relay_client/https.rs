//! Direct HTTPS relay dialer for the clearnet fast path.
//!
//! This module deliberately handles only relay delivery. Peer identity, Double Ratchet state,
//! attachments and pairing secrets never enter it: the caller gives it the already-serialized
//! versioned relay request containing opaque encrypted blobs.
//!
//! Privacy note: unlike Tor, direct HTTPS reveals the client's IP address and timing to the relay
//! host / network provider. TLS protects the request on the wire, but it is not an anonymity layer.

use std::io::{BufRead, BufReader, Read, Write};
use std::net::{TcpStream, ToSocketAddrs};
use std::sync::Arc;
use std::time::Duration;

use rustls::pki_types::ServerName;
use rustls::{ClientConfig, ClientConnection, RootCertStore, StreamOwned};
use url::Url;

use super::RelayDialer;
use crate::Result;

const CONNECT_TIMEOUT: Duration = Duration::from_secs(8);
const IO_TIMEOUT: Duration = Duration::from_secs(15);
const MAX_HEADER_BYTES: usize = 64 * 1024;
// A mailbox can hold 256 MiB of raw blobs; base64 + JSON can be roughly 4/3 larger.
const MAX_RESPONSE_BYTES: usize = 384 * 1024 * 1024;

#[derive(Clone, Debug)]
struct Endpoint {
    host: String,
    port: u16,
    path: String,
    host_header: String,
}

impl Endpoint {
    fn parse(input: &str) -> Result<Self> {
        let url = Url::parse(input)?;
        if url.scheme() != "https" {
            anyhow::bail!("HTTPS relay URL must use https://");
        }
        if !url.username().is_empty() || url.password().is_some() {
            anyhow::bail!("HTTPS relay URL must not contain credentials");
        }
        if url.query().is_some() || url.fragment().is_some() {
            anyhow::bail!("HTTPS relay URL must not contain query or fragment");
        }

        let host = url
            .host_str()
            .ok_or_else(|| anyhow::anyhow!("HTTPS relay URL has no host"))?
            .to_string();
        let port = url
            .port_or_known_default()
            .ok_or_else(|| anyhow::anyhow!("HTTPS relay URL has no port"))?;
        let path = if url.path().is_empty() || url.path() == "/" {
            "/v1/relay".to_string()
        } else {
            url.path().to_string()
        };
        let host_header = if port == 443 {
            host.clone()
        } else {
            format!("{host}:{port}")
        };

        Ok(Self {
            host,
            port,
            path,
            host_header,
        })
    }
}

/// Build a blocking relay dialer that POSTs the existing relay JSON envelope over TLS 1.2/1.3.
///
/// The endpoint may be either a bare HTTPS origin (the path defaults to /v1/relay) or an explicit
/// HTTPS path. It never accepts http://, credentials, query strings, or fragments.
pub fn https_relay_dialer(endpoint: &str) -> Result<RelayDialer> {
    let endpoint = Endpoint::parse(endpoint)?;

    let roots = RootCertStore::from_iter(webpki_roots::TLS_SERVER_ROOTS.iter().cloned());
    let mut config = ClientConfig::builder()
        .with_root_certificates(roots)
        .with_no_client_auth();
    // We speak HTTP/1.1 ourselves; do not negotiate h2.
    config.alpn_protocols = vec![b"http/1.1".to_vec()];
    let config = Arc::new(config);

    Ok(Arc::new(move |line: &str| {
        round_trip(&endpoint, Arc::clone(&config), line)
    }))
}

fn round_trip(endpoint: &Endpoint, config: Arc<ClientConfig>, line: &str) -> Result<String> {
    let mut last_error = None;
    let mut socket = None;
    for addr in (endpoint.host.as_str(), endpoint.port).to_socket_addrs()? {
        match TcpStream::connect_timeout(&addr, CONNECT_TIMEOUT) {
            Ok(s) => {
                socket = Some(s);
                break;
            }
            Err(e) => last_error = Some(e),
        }
    }
    let socket = match socket {
        Some(s) => s,
        None => {
            return Err(last_error
                .map(anyhow::Error::from)
                .unwrap_or_else(|| anyhow::anyhow!("HTTPS relay host resolved to no addresses")))
        }
    };
    socket.set_read_timeout(Some(IO_TIMEOUT))?;
    socket.set_write_timeout(Some(IO_TIMEOUT))?;

    let server_name = ServerName::try_from(endpoint.host.clone())
        .map_err(|_| anyhow::anyhow!("invalid TLS server name"))?;
    let conn = ClientConnection::new(config, server_name)?;
    let mut tls = StreamOwned::new(conn, socket);

    write!(
        tls,
        "POST {} HTTP/1.1\r\nHost: {}\r\nContent-Type: application/json\r\nAccept: application/json\r\nContent-Length: {}\r\nCache-Control: no-store\r\nConnection: close\r\n\r\n",
        endpoint.path,
        endpoint.host_header,
        line.len()
    )?;
    tls.write_all(line.as_bytes())?;
    tls.flush()?;

    let mut reader = BufReader::new(tls);
    read_http_response(&mut reader)
}

fn read_http_response<R: BufRead>(reader: &mut R) -> Result<String> {
    let mut status_line = String::new();
    reader.read_line(&mut status_line)?;
    if status_line.is_empty() {
        anyhow::bail!("HTTPS relay returned an empty response");
    }

    let mut status_parts = status_line.split_whitespace();
    let version = status_parts.next().unwrap_or("");
    let status = status_parts
        .next()
        .and_then(|s| s.parse::<u16>().ok())
        .ok_or_else(|| anyhow::anyhow!("invalid HTTP status line"))?;
    if !version.starts_with("HTTP/1.") {
        anyhow::bail!("HTTPS relay returned unsupported HTTP version");
    }

    let mut header_bytes = status_line.len();
    let mut content_length = None;
    let mut chunked = false;
    loop {
        let mut line = String::new();
        reader.read_line(&mut line)?;
        header_bytes = header_bytes.saturating_add(line.len());
        if header_bytes > MAX_HEADER_BYTES {
            anyhow::bail!("HTTPS relay response headers too large");
        }
        if line == "\r\n" || line == "\n" || line.is_empty() {
            break;
        }
        let Some((name, value)) = line.split_once(':') else {
            anyhow::bail!("malformed HTTPS relay response header");
        };
        let value = value.trim();
        if name.trim().eq_ignore_ascii_case("content-length") {
            let len = value.parse::<usize>()?;
            if content_length.replace(len).is_some() {
                anyhow::bail!("duplicate content-length");
            }
        } else if name.trim().eq_ignore_ascii_case("transfer-encoding") {
            chunked = value
                .split(',')
                .any(|part| part.trim().eq_ignore_ascii_case("chunked"));
        }
    }

    if status != 200 {
        anyhow::bail!("HTTPS relay returned HTTP {status}");
    }

    let bytes = if chunked {
        read_chunked(reader)?
    } else if let Some(len) = content_length {
        if len > MAX_RESPONSE_BYTES {
            anyhow::bail!("HTTPS relay response too large");
        }
        let mut body = vec![0u8; len];
        reader.read_exact(&mut body)?;
        body
    } else {
        let mut body = Vec::new();
        reader
            .take((MAX_RESPONSE_BYTES + 1) as u64)
            .read_to_end(&mut body)?;
        if body.len() > MAX_RESPONSE_BYTES {
            anyhow::bail!("HTTPS relay response too large");
        }
        body
    };

    Ok(String::from_utf8(bytes)?)
}

fn read_chunked<R: BufRead>(reader: &mut R) -> Result<Vec<u8>> {
    let mut out = Vec::new();
    loop {
        let mut size_line = String::new();
        reader.read_line(&mut size_line)?;
        if size_line.len() > 1024 {
            anyhow::bail!("invalid chunk header");
        }
        let hex = size_line
            .trim()
            .split(';')
            .next()
            .ok_or_else(|| anyhow::anyhow!("invalid chunk header"))?;
        let size = usize::from_str_radix(hex, 16)?;
        if size == 0 {
            // Consume optional trailers.
            loop {
                let mut trailer = String::new();
                reader.read_line(&mut trailer)?;
                if trailer == "\r\n" || trailer == "\n" || trailer.is_empty() {
                    break;
                }
            }
            break;
        }
        if out.len().saturating_add(size) > MAX_RESPONSE_BYTES {
            anyhow::bail!("HTTPS relay response too large");
        }
        let start = out.len();
        out.resize(start + size, 0);
        reader.read_exact(&mut out[start..])?;

        let mut crlf = [0u8; 2];
        reader.read_exact(&mut crlf)?;
        if crlf != *b"\r\n" {
            anyhow::bail!("invalid chunk terminator");
        }
    }
    Ok(out)
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::io::Cursor;

    #[test]
    fn endpoint_defaults_to_relay_path() {
        let e = Endpoint::parse("https://relay.example").unwrap();
        assert_eq!(e.host, "relay.example");
        assert_eq!(e.port, 443);
        assert_eq!(e.path, "/v1/relay");
        assert_eq!(e.host_header, "relay.example");
    }

    #[test]
    fn endpoint_rejects_insecure_scheme_and_credentials() {
        assert!(Endpoint::parse("http://relay.example").is_err());
        assert!(Endpoint::parse("https://user:pass@relay.example").is_err());
    }

    #[test]
    fn reads_content_length_response() {
        let raw =
            b"HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: 4\r\n\r\nok\n\n";
        let mut reader = Cursor::new(raw.as_slice());
        assert_eq!(read_http_response(&mut reader).unwrap(), "ok\n\n");
    }

    #[test]
    fn reads_chunked_response() {
        let raw = b"HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n4\r\ntest\r\n3\r\n123\r\n0\r\n\r\n";
        let mut reader = Cursor::new(raw.as_slice());
        assert_eq!(read_http_response(&mut reader).unwrap(), "test123");
    }

    #[test]
    fn non_200_is_route_failure() {
        let raw = b"HTTP/1.1 503 Service Unavailable\r\nContent-Length: 0\r\n\r\n";
        let mut reader = Cursor::new(raw.as_slice());
        assert!(read_http_response(&mut reader)
            .unwrap_err()
            .to_string()
            .contains("HTTP 503"));
    }
}
