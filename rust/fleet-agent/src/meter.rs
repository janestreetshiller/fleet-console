//! Metered usage, billed through Ouros.
//!
//! The same locality argument as the license keys (`docs/FREEMIUM.md`): Ouros
//! already reaches this machine for the agent mailbox, so billing rides a local
//! signed record instead of a cloud call. Every turn the engine runs appends
//! one HMAC-signed record to the ledger under the FleetConsole support
//! directory; the Ouros bar (or a store webhook) reads and totals it offline.
//!
//! Record format: `FLTA-<base32 payload>.<base32 HMAC-SHA256>` where the
//! payload is a compact string of `|`-separated fields:
//!
//! ```text
//! v1|<agent>|<period yyyyMMdd>|<model>|<input tokens>|<output tokens>|<turns>
//! ```
//!
//! The signature is HMAC-SHA256 over the payload with the vendor secret — the
//! same secret family as `FLT1` license keys, so a mint and a bill validate
//! with the same offline machinery. `FLTB` can change everything after the
//! dash without breaking old records.

use hmac::{Hmac, Mac};
use sha2::Sha256;

pub const VENDOR_SECRET: &str = "fleet-console-license-v1";
pub const RECORD_PREFIX: &str = "FLTA-";
pub const PAYLOAD_VERSION: &str = "v1";
const BASE32_ALPHABET: &[u8] = b"ABCDEFGHIJKLMNOPQRSTUVWXYZ234567";

use std::fs::Permissions;
use std::io::Write;
use std::os::unix::fs::PermissionsExt;

pub type HmacSha256 = Hmac<Sha256>;

/// One metered turn: the raw counters the engine accumulated.
#[derive(Debug, Clone, Copy, Default, PartialEq, Eq)]
pub struct TurnUsage {
    pub input_tokens: u64,
    pub output_tokens: u64,
}

impl TurnUsage {
    pub fn is_zero(&self) -> bool {
        self.input_tokens == 0 && self.output_tokens == 0
    }
}

/// A validated meter record (payload already parsed).
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct MeterRecord {
    pub agent: String,
    pub period: String,
    pub model: String,
    pub input_tokens: u64,
    pub output_tokens: u64,
    pub turns: u64,
}

impl MeterRecord {
    /// The `|`-separated payload string this record signs.
    pub fn payload(&self) -> String {
        format!(
            "{}|{}|{}|{}|{}|{}|{}",
            PAYLOAD_VERSION,
            self.agent,
            self.period,
            self.model,
            self.input_tokens,
            self.output_tokens,
            self.turns
        )
    }
}

fn encode_base32(bytes: &[u8]) -> String {
    let mut result = String::new();
    let mut buffer: u32 = 0;
    let mut bits = 0;
    for &byte in bytes {
        buffer = (buffer << 8) | u32::from(byte);
        bits += 8;
        while bits >= 5 {
            bits -= 5;
            result.push(BASE32_ALPHABET[((buffer >> bits) & 0x1F) as usize] as char);
        }
    }
    if bits > 0 {
        result.push(BASE32_ALPHABET[((buffer << (5 - bits)) & 0x1F) as usize] as char);
    }
    result
}

fn decode_base32(string: &str) -> Option<Vec<u8>> {
    let lookup = |c: u8| -> Option<u8> {
        BASE32_ALPHABET
            .iter()
            .position(|&a| a == c.to_ascii_uppercase())
            .map(|i| i as u8)
    };
    let mut bytes = Vec::new();
    let mut buffer: u32 = 0;
    let mut bits = 0;
    for &c in string.as_bytes() {
        let value = lookup(c)?;
        buffer = (buffer << 5) | u32::from(value);
        bits += 5;
        if bits >= 8 {
            bits -= 8;
            bytes.push(((buffer >> bits) & 0xFF) as u8);
        }
    }
    Some(bytes)
}

fn hmac_bytes(payload: &str, secret: &str) -> [u8; 32] {
    let mut mac = HmacSha256::new_from_slice(secret.as_bytes())
        .expect("HMAC accepts any key length");
    mac.update(payload.as_bytes());
    let out = mac.finalize().into_bytes();
    let mut sig = [0u8; 32];
    sig.copy_from_slice(&out);
    sig
}

/// Signs one record into `FLTA-<payload-b32>.<sig-b32>`.
pub fn sign(record: &MeterRecord, secret: &str) -> String {
    let payload = record.payload();
    let sig = hmac_bytes(&payload, secret);
    format!(
        "{}{}.{}",
        RECORD_PREFIX,
        encode_base32(payload.as_bytes()),
        encode_base32(&sig)
    )
}

/// Validates and parses a signed record. Mirrors `LicenseKey.isValid`: a
/// record that validates today validates in ten years.
pub fn verify(record: &str, secret: &str) -> Option<MeterRecord> {
    let rest = record.strip_prefix(RECORD_PREFIX)?;
    let (payload_b32, sig_b32) = rest.split_once('.')?;
    let payload_bytes = decode_base32(payload_b32)?;
    let sig_bytes = decode_base32(sig_b32)?;
    let payload = std::str::from_utf8(&payload_bytes).ok()?;
    let expected = hmac_bytes(payload, secret);
    if !constant_time_eq(&sig_bytes, &expected) {
        return None;
    }
    parse_payload(payload)
}

fn constant_time_eq(a: &[u8], b: &[u8]) -> bool {
    if a.len() != b.len() {
        return false;
    }
    let mut diff = 0u8;
    for (x, y) in a.iter().zip(b.iter()) {
        diff |= x ^ y;
    }
    diff == 0
}

fn parse_payload(payload: &str) -> Option<MeterRecord> {
    let fields: Vec<&str> = payload.split('|').collect();
    if fields.len() != 7 || fields[0] != PAYLOAD_VERSION {
        return None;
    }
    Some(MeterRecord {
        agent: fields[1].to_string(),
        period: fields[2].to_string(),
        model: fields[3].to_string(),
        input_tokens: fields[4].parse().ok()?,
        output_tokens: fields[5].parse().ok()?,
        turns: fields[6].parse().ok()?,
    })
}

/// The local period key (UTC `yyyyMMdd`) for a unix-seconds timestamp.
pub fn period_for_timestamp(secs: i64) -> String {
    let days = secs.div_euclid(86_400);
    let (y, m, d) = civil_from_days(days);
    format!("{y:04}{m:02}{d:02}")
}

/// Howard Hinnant's `civil_from_days` (canonical form, verified against the
/// published algorithm), UTC, dependency-free.
fn civil_from_days(z: i64) -> (i64, u32, u32) {
    let z = z + 719_468;
    let era = if z >= 0 { z } else { z - 146_096 } / 146_097;
    let doe = z - era * 146_097;                                        // [0, 146096]
    let yoe = (doe - doe / 1460 + doe / 36_524 - doe / 146_096) / 365;  // [0, 399]
    let y = yoe + era * 400;
    let doy = doe - (365 * yoe + yoe / 4 - yoe / 100);                  // [0, 365]
    let mp = (5 * doy + 2) / 153;                                       // [0, 11]
    let d = (doy - (153 * mp + 2) / 5 + 1) as u32;                       // [1, 31]
    let m = if mp < 10 { mp + 3 } else { mp - 9 } as u32;                // [1, 12]
    (if m <= 2 { y + 1 } else { y }, m, d)
}

/// Totals a ledger file's records: (valid records, invalid lines, summed usage).
pub fn total_ledger(
    path: &std::path::Path,
    secret: &str,
) -> std::io::Result<(Vec<MeterRecord>, usize, TurnUsage)> {
    let contents = match std::fs::read_to_string(path) {
        Ok(c) => c,
        Err(e) if e.kind() == std::io::ErrorKind::NotFound => return Ok((Vec::new(), 0, TurnUsage::default())),
        Err(e) => return Err(e),
    };
    let mut records = Vec::new();
    let mut invalid = 0usize;
    let mut usage = TurnUsage::default();
    for line in contents.lines().filter(|l| !l.trim().is_empty()) {
        match verify(line, secret) {
            Some(record) => {
                usage.input_tokens += record.input_tokens;
                usage.output_tokens += record.output_tokens;
                records.push(record);
            }
            None => invalid += 1,
        }
    }
    Ok((records, invalid, usage))
}

/// Appends one signed record to the ledger, creating it 0600 with 0700 dirs.
pub fn append_ledger(
    path: &std::path::Path,
    record: &MeterRecord,
    secret: &str,
) -> std::io::Result<()> {
    if let Some(parent) = path.parent() {
        std::fs::create_dir_all(parent)?;
        let _ = std::fs::set_permissions(parent, Permissions::from_mode(0o700));
    }
    let line = format!("{}\n", sign(record, secret));
    let mut options = std::fs::OpenOptions::new();
    options.create(true).append(true);
    let mut file = options.open(path)?;
    let _ = file.set_permissions(Permissions::from_mode(0o600));
    file.write_all(line.as_bytes())
}

#[cfg(test)]
mod tests {
    use super::*;

    fn sample() -> MeterRecord {
        MeterRecord {
            agent: "fleet-agent".into(),
            period: "20261012".into(),
            model: "qwen3.5-9b-local".into(),
            input_tokens: 1500,
            output_tokens: 700,
            turns: 3,
        }
    }

    #[test]
    fn round_trips_through_signature() {
        let signed = sign(&sample(), VENDOR_SECRET);
        assert!(signed.starts_with(RECORD_PREFIX));
        assert_eq!(verify(&signed, VENDOR_SECRET), Some(sample()));
    }

    #[test]
    fn tampered_payload_is_rejected() {
        let signed = sign(&sample(), VENDOR_SECRET);
        // Flip the last payload character (before the '.').
        let mut bytes = signed.into_bytes();
        let dot = bytes.iter().position(|&b| b == b'.').unwrap();
        let idx = if dot > RECORD_PREFIX.len() { dot - 1 } else { RECORD_PREFIX.len() };
        bytes[idx] = if bytes[idx] == b'A' { b'B' } else { b'A' };
        let tampered = String::from_utf8(bytes).unwrap();
        assert!(verify(&tampered, VENDOR_SECRET).is_none());
    }

    #[test]
    fn wrong_secret_is_rejected() {
        let signed = sign(&sample(), "not-the-secret");
        assert!(verify(&signed, VENDOR_SECRET).is_none());
    }

    #[test]
    fn garbage_is_rejected() {
        assert!(verify("hello", VENDOR_SECRET).is_none());
        assert!(verify("FLTA-not-a-record", VENDOR_SECRET).is_none());
    }

    #[test]
    fn ledger_append_and_total_round_trip() {
        let dir = tempfile::tempdir().unwrap();
        let path = dir.path().join("nested").join("meter-ledger.txt");
        append_ledger(&path, &sample(), VENDOR_SECRET).unwrap();
        append_ledger(
            &path,
            &MeterRecord { input_tokens: 10, output_tokens: 5, turns: 1, ..sample() },
            VENDOR_SECRET,
        )
        .unwrap();
        std::fs::write(path.with_extension("junk"), "FLTA-garbage\n").ok().unwrap();
        let (records, invalid, usage) = total_ledger(&path, VENDOR_SECRET).unwrap();
        assert_eq!(records.len(), 2);
        assert_eq!(invalid, 0);
        assert_eq!(usage, TurnUsage { input_tokens: 1510, output_tokens: 705 });
    }

    #[test]
    fn invalid_ledger_lines_are_counted_not_hidden() {
        let dir = tempfile::tempdir().unwrap();
        let path = dir.path().join("ledger.txt");
        std::fs::write(&path, "FLTA-tampered.junk\n\n").unwrap();
        let (records, invalid, usage) = total_ledger(&path, VENDOR_SECRET).unwrap();
        assert!(records.is_empty());
        assert_eq!(invalid, 1);
        assert!(usage.is_zero());
    }

    #[test]
    fn period_is_utc_year_month_day() {
        assert_eq!(period_for_timestamp(1_760_230_400), "20251012"); // 2025-10-12T00:00:00Z
        assert_eq!(period_for_timestamp(0), "19700101");
        // Year boundary: 2027-01-01T00:00:00Z = 1798764800
        assert_eq!(period_for_timestamp(1_798_764_800), "20270101");
    }
}
