//! Admission to inference is explicit, serialized and fail-closed. This module
//! never starts, loads, restarts or reconfigures a model server.

use std::fs::{File, OpenOptions};
use std::os::fd::AsRawFd;
use std::os::unix::fs::OpenOptionsExt;
use std::path::Path;

pub const MAX_QUESTION_BYTES: usize = 32 * 1024;
pub const MAX_HISTORY_BYTES: usize = 32 * 1024;
pub const MAX_REQUEST_BYTES: usize = 256 * 1024;
pub const MAX_RESPONSE_BYTES: usize = 1024 * 1024;
pub const MAX_TOOL_CALLS: usize = 16;
pub const MAX_TOOL_ARGUMENT_BYTES: usize = 4096;
pub const MAX_TOOL_RESULT_BYTES: usize = 8192;
pub const MAX_OUTPUT_TOKENS: usize = 512;
pub const MAX_PROMPT_BYTES: usize = 24 * 1024;
pub const TURN_TIMEOUT: std::time::Duration = std::time::Duration::from_secs(45);
pub const ROUND_TIMEOUT: std::time::Duration = std::time::Duration::from_secs(15);

extern "C" {
    fn flock(fd: std::os::raw::c_int, operation: std::os::raw::c_int) -> std::os::raw::c_int;
}

/// OS advisory locks are released on exit/crash; the persistent lock file is
/// never removed, avoiding two live processes locking different inodes.
#[derive(Debug)]
pub struct InferenceLease {
    _file: File,
}

impl InferenceLease {
    pub fn acquire(path: &Path) -> Result<Self, String> {
        if let Some(parent) = path.parent() {
            std::fs::create_dir_all(parent)
                .map_err(|e| format!("inference lock directory: {e}"))?;
        }
        let file = OpenOptions::new()
            .read(true)
            .write(true)
            .create(true)
            .truncate(false)
            .mode(0o600)
            .open(path)
            .map_err(|e| format!("inference lock: {e}"))?;
        // LOCK_EX | LOCK_NB has the same values on Darwin and Linux.
        if unsafe { flock(file.as_raw_fd(), 2 | 4) } != 0 {
            let error = std::io::Error::last_os_error();
            return Err(format!(
                "inference busy: another Fleet Agent proposal is running ({error})"
            ));
        }
        Ok(Self { _file: file })
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Pressure {
    Normal,
    Warning,
    Critical,
}

#[derive(Debug, Clone, Copy)]
pub struct MemorySnapshot {
    pub pressure: Pressure,
    pub physical_bytes: u64,
    pub wired_bytes: u64,
    pub compressed_bytes: u64,
    pub swap_used_bytes: u64,
}

pub fn require_headroom(snapshot: Result<MemorySnapshot, String>) -> Result<(), String> {
    let snapshot =
        snapshot.map_err(|e| format!("inference refused: cannot verify memory headroom ({e})"))?;
    require_normal_pressure(Ok(snapshot.pressure))?;
    if snapshot.physical_bytes == 0 {
        return Err("inference refused: physical-memory sample is unavailable".into());
    }
    if snapshot.swap_used_bytes >= snapshot.physical_bytes / 4 {
        return Err("inference refused: swap usage is at least 25% of physical memory".into());
    }
    if snapshot
        .wired_bytes
        .saturating_add(snapshot.compressed_bytes)
        >= snapshot.physical_bytes / 4 * 3
    {
        return Err(
            "inference refused: wired and compressed memory occupy at least 75% of physical memory"
                .into(),
        );
    }
    Ok(())
}

pub fn require_normal_pressure(pressure: Result<Pressure, String>) -> Result<(), String> {
    match pressure {
        Ok(Pressure::Normal) => Ok(()),
        Ok(level) => Err(format!(
            "inference refused: macOS memory pressure is {level:?}"
        )),
        Err(error) => Err(format!(
            "inference refused: cannot verify memory pressure ({error})"
        )),
    }
}

#[cfg(target_os = "macos")]
pub fn sample_memory() -> Result<MemorySnapshot, String> {
    use std::ffi::{c_void, CStr};
    extern "C" {
        fn sysctlbyname(
            name: *const std::os::raw::c_char,
            oldp: *mut c_void,
            oldlenp: *mut usize,
            newp: *mut c_void,
            newlen: usize,
        ) -> std::os::raw::c_int;
        fn mach_host_self() -> u32;
        fn host_statistics64(host: u32, flavor: i32, output: *mut i32, count: *mut u32) -> i32;
        fn host_page_size(host: u32, size: *mut usize) -> i32;
        fn mach_port_deallocate(task: u32, port: u32) -> i32;
        static mach_task_self_: u32;
    }
    let mut value: i32 = 0;
    let mut length = std::mem::size_of_val(&value);
    let status = unsafe {
        sysctlbyname(
            c"kern.memorystatus_vm_pressure_level".as_ptr(),
            (&mut value as *mut i32).cast(),
            &mut length,
            std::ptr::null_mut(),
            0,
        )
    };
    if status != 0 || length != std::mem::size_of_val(&value) {
        return Err(std::io::Error::last_os_error().to_string());
    }
    let pressure = match value {
        1 => Pressure::Normal,
        2 => Pressure::Warning,
        4 => Pressure::Critical,
        other => return Err(format!("unknown kernel pressure level {other}")),
    };
    // The revision-1 prefix is stable in Apple's SDK vm_statistics.h. Asking
    // for this prefix works on the minimum supported macOS without relying on
    // newer tagged-memory fields appended by current SDKs.
    #[repr(C)]
    #[derive(Default)]
    struct VmStatisticsV1 {
        free: u32,
        active: u32,
        inactive: u32,
        wired: u32,
        counters: [u64; 9],
        purgeable: u32,
        speculative: u32,
        counters_v1: [u64; 4],
        compressor: u32,
        throttled: u32,
        external: u32,
        internal: u32,
        uncompressed: u64,
    }
    #[repr(C)]
    #[derive(Default)]
    struct SwapUsage {
        total: u64,
        available: u64,
        used: u64,
        page_size: u32,
        encrypted: i32,
    }
    fn read_sysctl<T>(name: &CStr, output: &mut T) -> Result<(), String> {
        let mut length = std::mem::size_of::<T>();
        let status = unsafe {
            sysctlbyname(
                name.as_ptr(),
                (output as *mut T).cast(),
                &mut length,
                std::ptr::null_mut(),
                0,
            )
        };
        if status != 0 || length != std::mem::size_of::<T>() {
            return Err(std::io::Error::last_os_error().to_string());
        }
        Ok(())
    }
    let mut physical = 0u64;
    let mut swap = SwapUsage::default();
    read_sysctl(c"hw.memsize", &mut physical)?;
    read_sysctl(c"vm.swapusage", &mut swap)?;
    let mut stats = VmStatisticsV1::default();
    let mut count = (std::mem::size_of_val(&stats) / std::mem::size_of::<i32>()) as u32;
    let expected_count = count;
    let mut page_size = 0usize;
    let host = unsafe { mach_host_self() };
    let vm_status = unsafe {
        host_statistics64(
            host,
            4,
            (&mut stats as *mut VmStatisticsV1).cast(),
            &mut count,
        )
    };
    let page_status = unsafe { host_page_size(host, &mut page_size) };
    unsafe {
        mach_port_deallocate(mach_task_self_, host);
    }
    if vm_status != 0 || page_status != 0 || count != expected_count || page_size == 0 {
        return Err(format!(
            "Mach memory sample failed (vm={vm_status}, pages={page_status}, count={count})"
        ));
    }
    Ok(MemorySnapshot {
        pressure,
        physical_bytes: physical,
        wired_bytes: u64::from(stats.wired) * page_size as u64,
        compressed_bytes: u64::from(stats.compressor) * page_size as u64,
        swap_used_bytes: swap.used,
    })
}

#[cfg(not(target_os = "macos"))]
pub fn sample_memory() -> Result<MemorySnapshot, String> {
    Err("memory-pressure admission is supported on macOS only".into())
}

pub fn check_question(question: &str) -> Result<(), String> {
    if question.len() > MAX_QUESTION_BYTES {
        return Err(format!("proposal input exceeds {MAX_QUESTION_BYTES} bytes"));
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn pressure_admission_fails_closed() {
        assert!(require_normal_pressure(Ok(Pressure::Normal)).is_ok());
        assert!(require_normal_pressure(Ok(Pressure::Warning)).is_err());
        assert!(require_normal_pressure(Ok(Pressure::Critical)).is_err());
        assert!(require_normal_pressure(Err("unavailable".into())).is_err());
    }

    #[test]
    fn inference_lock_is_exclusive_and_released_by_close() {
        let dir = tempfile::tempdir().unwrap();
        let path = dir.path().join("inference.lock");
        let lease = InferenceLease::acquire(&path).unwrap();
        assert!(InferenceLease::acquire(&path).unwrap_err().contains("busy"));
        drop(lease);
        assert!(InferenceLease::acquire(&path).is_ok());
    }

    #[test]
    fn question_bound_is_exact() {
        assert!(check_question(&"x".repeat(MAX_QUESTION_BYTES)).is_ok());
        assert!(check_question(&"x".repeat(MAX_QUESTION_BYTES + 1)).is_err());
    }

    #[test]
    fn original_incident_is_refused_even_with_normal_kernel_pressure() {
        let gib = 1024 * 1024 * 1024;
        let incident = MemorySnapshot {
            pressure: Pressure::Normal,
            physical_bytes: 16 * gib,
            wired_bytes: 733_000 * 16_384,
            compressed_bytes: 5 * gib / 2,
            swap_used_bytes: 14 * gib,
        };
        assert!(require_headroom(Ok(incident)).unwrap_err().contains("swap"));
        assert!(require_headroom(Ok(MemorySnapshot {
            swap_used_bytes: 0,
            ..incident
        }))
        .unwrap_err()
        .contains("wired"));
        let healthy = MemorySnapshot {
            wired_bytes: gib,
            compressed_bytes: gib / 2,
            swap_used_bytes: 0,
            ..incident
        };
        assert!(require_headroom(Ok(healthy)).is_ok());
        assert!(require_headroom(Err("sample denied".into())).is_err());
        assert!(require_headroom(Ok(MemorySnapshot {
            swap_used_bytes: 4 * gib,
            ..healthy
        }))
        .is_err());
    }

    #[cfg(target_os = "macos")]
    #[test]
    fn live_mach_and_sysctl_sample_has_valid_units() {
        let snapshot = sample_memory().unwrap();
        assert!(snapshot.physical_bytes >= 1024 * 1024 * 1024);
        assert!(snapshot.wired_bytes <= snapshot.physical_bytes);
        assert!(snapshot.compressed_bytes <= snapshot.physical_bytes);
    }
}
