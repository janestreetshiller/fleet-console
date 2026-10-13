//! Minimal std-only HTTP client for the local llama-server. No TLS, no
//! redirects, no proxying: it speaks to 127.0.0.1 only, and the URL is
//! validated to be a loopback origin before any connection is made.

use serde_json::Value;
use std::io::{BufRead, BufReader, Read, Write};
use std::net::TcpStream;
use std::time::Duration;

pub struct Http {
    timeout: Duration,
}

impl Http {
    pub fn new(timeout: Duration) -> Self {
        Self { timeout }
    }

    /// Parse and validate the origin; refuse anything that is not plain HTTP
    /// on a loopback address. The agent must never be able to point its
    /// model traffic at the network by env var alone.
    pub fn loopback_origin(url: &str) -> Result<String, String> {
        let (host, port) = parse_host_port(url)?;
        // Exact loopback forms only: a DNS suffix (127.0.0.1.evil) or a
        // bracketed anything is refused. localhost is included because
        // llama-server binds it on this machine.
        let is_loopback = host == "127.0.0.1" || host == "localhost" || host == "[::1]" || host == "::1";
        if !is_loopback {
            return Err(format!(
                "refusing non-loopback model endpoint {host}:{port} — the resident agent runs on \
                 local inference only"
            ));
        }
        Ok(format!("{host}:{port}"))
    }

    pub fn post_json(&mut self, url: &str, body: &Value) -> Result<Value, String> {
        let authority = Self::loopback_origin(url)?;
        let path = url
            .split_once("://")
            .map(|(_, rest)| rest)
            .and_then(|rest| rest.find('/').map(|i| &rest[i..]))
            .unwrap_or("/")
            .to_string();
        let payload = serde_json::to_string(body).map_err(|e| e.to_string())?;
        let mut stream = TcpStream::connect(&authority).map_err(|e| e.to_string())?;
        stream.set_read_timeout(Some(self.timeout)).map_err(|e| e.to_string())?;
        stream.set_write_timeout(Some(self.timeout)).map_err(|e| e.to_string())?;

        let request = format!(
            "POST {path} HTTP/1.1\r\nHost: {authority}\r\nContent-Type: application/json\r\nContent-Length: {}\r\nConnection: close\r\n\r\n{payload}",
            payload.len()
        );
        stream.write_all(request.as_bytes()).map_err(|e| e.to_string())?;

        let mut reader = BufReader::new(stream);
        let mut status_line = String::new();
        reader.read_line(&mut status_line).map_err(|e| e.to_string())?;
        if !status_line.contains("200") {
            return Err(format!("model endpoint returned {status_line}"));
        }
        let mut content_length: Option<usize> = None;
        let mut chunked = false;
        loop {
            let mut line = String::new();
            if reader.read_line(&mut line).map_err(|e| e.to_string())? == 0 {
                break;
            }
            let trimmed = line.trim();
            if trimmed.is_empty() {
                break;
            }
            let lower = trimmed.to_ascii_lowercase();
            if let Some(len) = lower.strip_prefix("content-length:") {
                content_length = len.trim().parse().ok();
            } else if lower.starts_with("transfer-encoding:") && lower.contains("chunked") {
                chunked = true;
            }
        }
        let mut body_raw = String::new();
        if chunked {
            loop {
                let mut size_line = String::new();
                if reader.read_line(&mut size_line).map_err(|e| e.to_string())? == 0 {
                    break;
                }
                let size = usize::from_str_radix(size_line.trim(), 16).unwrap_or(0);
                if size == 0 {
                    break;
                }
                let mut chunk = vec![0u8; size];
                std::io::Read::read_exact(&mut reader, &mut chunk).map_err(|e| e.to_string())?;
                body_raw.push_str(&String::from_utf8_lossy(&chunk));
                let mut crlf = String::new();
                let _ = reader.read_line(&mut crlf);
            }
        } else if let Some(len) = content_length {
            let mut buf = vec![0u8; len];
            std::io::Read::read_exact(&mut reader, &mut buf).map_err(|e| e.to_string())?;
            body_raw = String::from_utf8_lossy(&buf).to_string();
        } else {
            let mut sink = String::new();
            reader.read_to_string(&mut sink).map_err(|e| e.to_string())?;
            body_raw = sink;
        }
        serde_json::from_str(&body_raw).map_err(|e| format!("model reply is not JSON: {e}"))
    }
}

fn parse_host_port(url: &str) -> Result<(String, u16), String> {
    let rest = url
        .strip_prefix("http://")
        .ok_or_else(|| format!("refusing {url}: only plain http to loopback is allowed"))?;
    let authority = rest.split('/').next().unwrap_or(rest);
    if let Some((host, port_str)) = authority.rsplit_once(':') {
        let port: u16 = port_str.parse().map_err(|_| format!("bad port in {url}"))?;
        Ok((host.to_string(), port))
    } else {
        Ok((authority.to_string(), 80))
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn refuses_non_loopback() {
        assert!(Http::loopback_origin("http://192.168.1.5:8081").is_err());
        assert!(Http::loopback_origin("http://example.com:80").is_err());
        assert!(Http::loopback_origin("https://127.0.0.1:8081").is_err());
        assert!(Http::loopback_origin("http://127.0.0.1.evil:8081").is_err());
    }

    #[test]
    fn accepts_loopback_forms() {
        assert!(Http::loopback_origin("http://127.0.0.1:53144/v1/chat/completions").is_ok());
        assert!(Http::loopback_origin("http://localhost:8081/").is_ok());
    }
}
