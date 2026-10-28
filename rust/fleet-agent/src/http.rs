//! Bounded HTTP to an existing loopback endpoint. No redirects, proxy, DNS,
//! model startup, retry or unbounded allocation; every IO shares one deadline.
use crate::guard::{MAX_REQUEST_BYTES, MAX_RESPONSE_BYTES};
use serde_json::Value;
use std::io::{BufRead, BufReader, Read, Write};
use std::net::{IpAddr, SocketAddr, TcpStream};
use std::time::{Duration, Instant};
const MAX_HEADER_BYTES: usize = 16 * 1024;
const MAX_HEADER_LINE_BYTES: usize = 4096;
pub struct Http {
    timeout: Duration,
}
impl Http {
    pub fn new(timeout: Duration) -> Self {
        Self { timeout }
    }
    pub fn loopback_origin(url: &str) -> Result<String, String> {
        let (host, port) = parse_host_port(url)?;
        if !matches!(host.as_str(), "127.0.0.1" | "localhost" | "[::1]") {
            return Err(format!(
                "refusing non-loopback model endpoint {host}:{port}"
            ));
        }
        Ok(format!("{host}:{port}"))
    }
    pub fn post_json(&mut self, url: &str, body: &Value) -> Result<Value, String> {
        self.post_json_until(url, body, Instant::now() + self.timeout)
    }
    pub fn post_json_until(
        &mut self,
        url: &str,
        body: &Value,
        deadline: Instant,
    ) -> Result<Value, String> {
        let deadline = deadline.min(Instant::now() + self.timeout);
        let authority = Self::loopback_origin(url)?;
        let (host, port) = parse_host_port(url)?;
        let ip: IpAddr = if host == "[::1]" { "::1" } else { "127.0.0.1" }
            .parse()
            .unwrap();
        let path = url
            .strip_prefix("http://")
            .unwrap()
            .find('/')
            .map(|index| &url["http://".len() + index..])
            .unwrap_or("/");
        if path.contains(['\r', '\n', '#']) {
            return Err("invalid model endpoint path".into());
        }
        let mut payload = LimitedBytes::new(MAX_REQUEST_BYTES);
        serde_json::to_writer(&mut payload, body).map_err(|e| {
            format!("model request exceeds {MAX_REQUEST_BYTES} bytes or cannot serialize: {e}")
        })?;
        let mut stream =
            TcpStream::connect_timeout(&SocketAddr::new(ip, port), remaining(deadline)?)
                .map_err(|e| format!("model endpoint unavailable: {e}"))?;
        let header = format!("POST {path} HTTP/1.1\r\nHost: {authority}\r\nContent-Type: application/json\r\nContent-Length: {}\r\nConnection: close\r\n\r\n", payload.bytes.len());
        write_until(&mut stream, header.as_bytes(), deadline)?;
        write_until(&mut stream, &payload.bytes, deadline)?;
        let mut reader = DeadlineReader {
            reader: BufReader::new(stream),
            deadline,
        };
        let status_line = reader.line(MAX_HEADER_LINE_BYTES)?;
        if status_line.split_whitespace().nth(1) != Some("200") {
            return Err(format!("model endpoint returned {}", status_line.trim()));
        }
        let mut header_bytes = status_line.len();
        let mut content_length = None;
        let mut chunked = false;
        loop {
            let line = reader.line(MAX_HEADER_LINE_BYTES)?;
            header_bytes += line.len();
            if header_bytes > MAX_HEADER_BYTES {
                return Err("model HTTP headers exceed limit".into());
            }
            if line.trim().is_empty() {
                break;
            }
            let lower = line.trim().to_ascii_lowercase();
            if let Some(length) = lower.strip_prefix("content-length:") {
                let value: usize = length
                    .trim()
                    .parse()
                    .map_err(|_| "invalid content-length")?;
                if value > MAX_RESPONSE_BYTES {
                    return Err(format!("model response exceeds {MAX_RESPONSE_BYTES} bytes"));
                }
                if content_length.replace(value).is_some() {
                    return Err("duplicate content-length".into());
                }
            } else if let Some(encoding) = lower.strip_prefix("transfer-encoding:") {
                if encoding.trim() != "chunked" {
                    return Err("unsupported transfer encoding".into());
                }
                chunked = true;
            }
        }
        if chunked && content_length.is_some() {
            return Err("ambiguous HTTP body framing".into());
        }
        let mut raw = Vec::new();
        if chunked {
            loop {
                let line = reader.line(MAX_HEADER_LINE_BYTES)?;
                let size = usize::from_str_radix(line.trim().split(';').next().unwrap_or(""), 16)
                    .map_err(|_| "invalid chunk size")?;
                if size == 0 {
                    break;
                }
                if size > MAX_RESPONSE_BYTES - raw.len() {
                    return Err(format!("model response exceeds {MAX_RESPONSE_BYTES} bytes"));
                }
                reader.append_exact(&mut raw, size)?;
                if reader.line(2)? != "\r\n" {
                    return Err("invalid chunk delimiter".into());
                }
            }
        } else if let Some(length) = content_length {
            reader.append_exact(&mut raw, length)?;
        } else {
            let mut chunk = [0u8; 8192];
            loop {
                reader.set_timeout()?;
                let read = reader
                    .reader
                    .read(&mut chunk)
                    .map_err(|e| format!("model response read: {e}"))?;
                if read == 0 {
                    break;
                }
                if read > MAX_RESPONSE_BYTES - raw.len() {
                    return Err(format!("model response exceeds {MAX_RESPONSE_BYTES} bytes"));
                }
                raw.extend_from_slice(&chunk[..read]);
            }
        }
        remaining(deadline)?;
        serde_json::from_slice(&raw).map_err(|e| format!("model reply is not JSON: {e}"))
    }
}
/// Serializes through a cap rather than allocating arbitrarily large JSON first.
pub struct LimitedBytes {
    pub bytes: Vec<u8>,
    maximum: usize,
}
impl LimitedBytes {
    pub fn new(maximum: usize) -> Self {
        Self {
            bytes: Vec::new(),
            maximum,
        }
    }
}
impl Write for LimitedBytes {
    fn write(&mut self, bytes: &[u8]) -> std::io::Result<usize> {
        if bytes.len() > self.maximum - self.bytes.len() {
            return Err(std::io::Error::new(
                std::io::ErrorKind::InvalidData,
                "byte limit exceeded",
            ));
        }
        self.bytes.extend_from_slice(bytes);
        Ok(bytes.len())
    }
    fn flush(&mut self) -> std::io::Result<()> {
        Ok(())
    }
}
pub fn remaining(deadline: Instant) -> Result<Duration, String> {
    deadline
        .checked_duration_since(Instant::now())
        .filter(|d| !d.is_zero())
        .ok_or_else(|| "proposal deadline exceeded".to_string())
}
fn write_until(stream: &mut TcpStream, mut bytes: &[u8], deadline: Instant) -> Result<(), String> {
    while !bytes.is_empty() {
        stream
            .set_write_timeout(Some(remaining(deadline)?))
            .map_err(|e| e.to_string())?;
        let written = stream
            .write(bytes)
            .map_err(|e| format!("model request write: {e}"))?;
        if written == 0 {
            return Err("model endpoint closed while writing".into());
        }
        bytes = &bytes[written..];
    }
    Ok(())
}
struct DeadlineReader {
    reader: BufReader<TcpStream>,
    deadline: Instant,
}
impl DeadlineReader {
    fn set_timeout(&self) -> Result<(), String> {
        self.reader
            .get_ref()
            .set_read_timeout(Some(remaining(self.deadline)?))
            .map_err(|e| e.to_string())
    }
    fn line(&mut self, maximum: usize) -> Result<String, String> {
        let mut bytes = Vec::new();
        loop {
            self.set_timeout()?;
            let available = self
                .reader
                .fill_buf()
                .map_err(|e| format!("model HTTP read: {e}"))?;
            if available.is_empty() {
                return Err("model endpoint closed before complete headers/chunk".into());
            }
            let end = available.iter().position(|b| *b == b'\n').map(|i| i + 1);
            let count = end.unwrap_or(available.len());
            if count > maximum - bytes.len() {
                return Err("model HTTP line exceeds limit".into());
            }
            bytes.extend_from_slice(&available[..count]);
            self.reader.consume(count);
            if end.is_some() {
                return String::from_utf8(bytes).map_err(|_| "model HTTP line is not UTF-8".into());
            }
        }
    }
    fn append_exact(&mut self, bytes: &mut Vec<u8>, length: usize) -> Result<(), String> {
        let mut left = length;
        let mut chunk = [0u8; 8192];
        while left > 0 {
            self.set_timeout()?;
            let count = left.min(chunk.len());
            let read = self
                .reader
                .read(&mut chunk[..count])
                .map_err(|e| format!("model body read: {e}"))?;
            if read == 0 {
                return Err("model endpoint closed before complete body".into());
            }
            bytes.extend_from_slice(&chunk[..read]);
            left -= read;
        }
        Ok(())
    }
}
fn parse_host_port(url: &str) -> Result<(String, u16), String> {
    let rest = url
        .strip_prefix("http://")
        .ok_or_else(|| "only plain HTTP to loopback is allowed".to_string())?;
    let authority = rest.split('/').next().unwrap_or(rest);
    if authority.len() > 128 || authority.contains(['\r', '\n', '?', '#', '@']) {
        return Err("invalid model endpoint authority".into());
    }
    if let Some((host, port)) = authority.rsplit_once(':') {
        let port = port
            .parse::<u16>()
            .map_err(|_| "invalid model endpoint port")?;
        if port == 0 {
            return Err("invalid model endpoint port 0".into());
        }
        Ok((host.into(), port))
    } else {
        Ok((authority.into(), 80))
    }
}
#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn refuses_non_loopback_and_header_injection() {
        for url in [
            "http://192.168.1.5:8081",
            "http://example.com:80",
            "https://127.0.0.1:8081",
            "http://127.0.0.1.evil:8081",
            "http://localhost:1\r\nHost: evil",
        ] {
            assert!(Http::loopback_origin(url).is_err(), "{url}");
        }
    }
    #[test]
    fn accepts_loopback_forms() {
        assert!(Http::loopback_origin("http://127.0.0.1:53144/v1/chat/completions").is_ok());
        assert!(Http::loopback_origin("http://localhost:8081/").is_ok());
        assert!(Http::loopback_origin("http://[::1]:8081/").is_ok());
    }
}
