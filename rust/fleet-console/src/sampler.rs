use std::path::Path;
use std::time::Duration;

pub const SAMPLE_INTERVAL: Duration = Duration::from_secs(2);

#[derive(Debug, Clone, Copy, Default, PartialEq, Eq)]
pub struct Meters {
    pub cpu: Option<u32>,
    pub ram: Option<u32>,
    pub disk: Option<u32>,
}

impl Meters {
    pub fn text(self) -> String {
        format!(
            "CPU {}   RAM {}   DISK {}",
            value_text(self.cpu),
            value_text(self.ram),
            value_text(self.disk)
        )
    }

    pub fn accessibility(self) -> String {
        format!(
            "FleetConsole fleet — CPU {}, RAM {}, DISK {}",
            value_text(self.cpu),
            value_text(self.ram),
            value_text(self.disk)
        )
    }
}

pub fn value_text(value: Option<u32>) -> String {
    match value {
        Some(percent) => format!("{percent}%"),
        None => "—".to_string(),
    }
}

fn percent_of(share: f64) -> Option<u32> {
    if share.is_finite() {
        Some((share.clamp(0.0, 1.0) * 100.0).round() as u32)
    } else {
        None
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Pressure {
    Normal,
    Warning,
    Critical,
    Unknown,
}

impl Pressure {
    pub fn label(self) -> &'static str {
        match self {
            Pressure::Normal => "normal",
            Pressure::Warning => "elevated",
            Pressure::Critical => "critical",
            Pressure::Unknown => "unknown",
        }
    }
}

#[derive(Debug, Clone, PartialEq)]
pub struct DiskRow {
    pub name: String,
    pub mount: String,
    pub total: u64,
    pub available: u64,
}

#[derive(Debug, Clone, PartialEq)]
pub struct ProcRow {
    pub pid: u32,
    pub name: String,
    pub cpu_pct: f32,
    pub mem_bytes: u64,
}

pub fn collect_processes(system: &mut sysinfo::System) -> Vec<ProcRow> {
    system.refresh_processes(sysinfo::ProcessesToUpdate::All);
    let mut rows: Vec<ProcRow> = system
        .processes()
        .values()
        .map(|process| ProcRow {
            pid: process.pid().as_u32(),
            name: process.name().to_string_lossy().into_owned(),
            cpu_pct: process.cpu_usage(),
            mem_bytes: process.memory(),
        })
        .collect();
    rows.sort_by(|a, b| {
        b.cpu_pct
            .partial_cmp(&a.cpu_pct)
            .unwrap_or(std::cmp::Ordering::Equal)
    });
    rows.truncate(25);
    rows
}

#[derive(Debug, Clone)]
pub struct Sample {
    pub meters: Meters,
    pub cpu_share: Option<f64>,
    pub mem_share: Option<f64>,
    pub mem_used_bytes: u64,
    pub mem_total_bytes: u64,
    pub mem_pressure: Pressure,
    pub disk_share: Option<f64>,
    pub disk_available: u64,
    pub disk_total: u64,
    pub disks: Vec<DiskRow>,
    pub net_down_bps: Option<f64>,
    pub net_up_bps: Option<f64>,
    pub cpu_help: String,
}

pub struct Sampler {
    system: sysinfo::System,
    disks: sysinfo::Disks,
    networks: sysinfo::Networks,
    cpu_primed: bool,
    network_primed: bool,
    cpu_help: String,
}

impl Default for Sampler {
    fn default() -> Self {
        Self::new()
    }
}

impl Sampler {
    pub fn new() -> Self {
        let mut system = sysinfo::System::new();
        system.refresh_cpu_usage();
        system.refresh_memory();
        let cpu_help = cpu_help(&system);
        Self {
            system,
            disks: sysinfo::Disks::new_with_refreshed_list(),
            networks: sysinfo::Networks::new_with_refreshed_list(),
            cpu_primed: false,
            network_primed: false,
            cpu_help,
        }
    }

    pub fn sample(&mut self) -> Sample {
        self.system.refresh_cpu_usage();
        self.system.refresh_memory();
        self.disks.refresh();
        self.networks.refresh();
        let cpu_share = if self.cpu_primed {
            let usage = self.system.global_cpu_usage();
            if usage.is_finite() {
                Some((usage.clamp(0.0, 100.0) / 100.0) as f64)
            } else {
                None
            }
        } else {
            None
        };
        self.cpu_primed = true;
        let (mem_used_bytes, mem_total_bytes) = memory_bytes(&self.system);
        let mem_share = if mem_total_bytes > 0 {
            Some(mem_used_bytes as f64 / mem_total_bytes as f64)
        } else {
            None
        };
        let (disk_share, disk_available, disk_total) = disk_reading(&self.disks);
        let disks = self
            .disks
            .list()
            .iter()
            .map(|disk| DiskRow {
                name: disk.name().to_string_lossy().into_owned(),
                mount: disk.mount_point().to_string_lossy().into_owned(),
                total: disk.total_space(),
                available: disk.available_space(),
            })
            .collect();
        let (net_down_bps, net_up_bps) = if self.network_primed {
            network_rates(&self.networks)
        } else {
            (None, None)
        };
        self.network_primed = true;
        Sample {
            meters: Meters {
                cpu: cpu_share.and_then(|share| percent_of(share)),
                ram: mem_share.and_then(|share| percent_of(share)),
                disk: disk_share.and_then(|share| percent_of(share)),
            },
            cpu_share,
            mem_share,
            mem_used_bytes,
            mem_total_bytes,
            mem_pressure: memory_pressure(),
            disk_share,
            disk_available,
            disk_total,
            disks,
            net_down_bps,
            net_up_bps,
            cpu_help: self.cpu_help.clone(),
        }
    }
}

fn disk_reading(disks: &sysinfo::Disks) -> (Option<f64>, u64, u64) {
    let Some(disk) = disks
        .list()
        .iter()
        .find(|disk| disk.mount_point() == Path::new("/"))
    else {
        return (None, 0, 0);
    };
    let total = disk.total_space();
    let available = disk.available_space();
    if total == 0 || available > total {
        return (None, available, total);
    }
    (
        Some((total - available) as f64 / total as f64),
        available,
        total,
    )
}

fn network_rates(networks: &sysinfo::Networks) -> (Option<f64>, Option<f64>) {
    let mut down: u64 = 0;
    let mut up: u64 = 0;
    let mut any = false;
    for (name, data) in networks.list() {
        if !is_physical_interface(name) {
            continue;
        }
        any = true;
        down = down.saturating_add(data.received());
        up = up.saturating_add(data.transmitted());
    }
    if !any {
        return (None, None);
    }
    let seconds = SAMPLE_INTERVAL.as_secs_f64();
    (
        Some(down as f64 / seconds),
        Some(up as f64 / seconds),
    )
}

fn is_physical_interface(name: &str) -> bool {
    const VIRTUAL_PREFIXES: [&str; 16] = [
        "lo", "utun", "awdl", "llw", "bridge", "anpi", "gif", "stf", "docker", "veth", "virbr",
        "br-", "tun", "tap", "wg", "ppp",
    ];
    !VIRTUAL_PREFIXES
        .iter()
        .any(|prefix| name.starts_with(prefix))
}

fn cpu_help(system: &sysinfo::System) -> String {
    let brand = system
        .cpus()
        .first()
        .map(|cpu| cpu.brand().trim().to_string())
        .filter(|brand| !brand.is_empty())
        .unwrap_or_else(|| "CPU".to_string());
    format!("{brand} · {}", core_summary(system))
}

#[cfg(target_os = "macos")]
fn core_summary(system: &sysinfo::System) -> String {
    let logical = system.cpus().len() as i64;
    if let (Some(level0), Some(level1)) = (
        sysctl_int("hw.perflevel0.logicalcpu"),
        sysctl_int("hw.perflevel1.logicalcpu"),
    ) {
        if level0 + level1 == logical && logical > 0 {
            let name0 = sysctl_string("hw.perflevel0.name")
                .unwrap_or_else(|| "performance".to_string())
                .to_lowercase();
            let performance_first = name0.starts_with('p');
            let (performance, efficiency) = if performance_first {
                (level0, level1)
            } else {
                (level1, level0)
            };
            return format!("{performance}P + {efficiency}E");
        }
    }
    format!("{logical} cores")
}

#[cfg(not(target_os = "macos"))]
fn core_summary(system: &sysinfo::System) -> String {
    let logical = system.cpus().len();
    let physical = system.physical_core_count().unwrap_or(logical);
    format!("{physical} cores")
}

#[cfg(target_os = "macos")]
fn sysctl_int(name: &str) -> Option<i64> {
    let cname = std::ffi::CString::new(name).ok()?;
    let mut value: i64 = 0;
    let mut size = std::mem::size_of::<i64>();
    let status = unsafe {
        libc::sysctlbyname(
            cname.as_ptr(),
            &mut value as *mut i64 as *mut libc::c_void,
            &mut size,
            std::ptr::null_mut(),
            0,
        )
    };
    (status == 0).then_some(value)
}

#[cfg(target_os = "macos")]
fn sysctl_string(name: &str) -> Option<String> {
    let cname = std::ffi::CString::new(name).ok()?;
    let mut size: usize = 0;
    let status = unsafe {
        libc::sysctlbyname(
            cname.as_ptr(),
            std::ptr::null_mut(),
            &mut size,
            std::ptr::null_mut(),
            0,
        )
    };
    if status != 0 || size == 0 {
        return None;
    }
    let mut buffer = vec![0u8; size];
    let status = unsafe {
        libc::sysctlbyname(
            cname.as_ptr(),
            buffer.as_mut_ptr() as *mut libc::c_void,
            &mut size,
            std::ptr::null_mut(),
            0,
        )
    };
    if status != 0 {
        return None;
    }
    buffer.retain(|byte| *byte != 0);
    String::from_utf8(buffer).ok()
}

#[cfg(target_os = "macos")]
fn memory_pressure() -> Pressure {
    let cname = match std::ffi::CString::new("kern.memorystatus_vm_pressure_level") {
        Ok(name) => name,
        Err(_) => return Pressure::Unknown,
    };
    let mut level: i32 = 0;
    let mut size = std::mem::size_of::<i32>();
    let status = unsafe {
        libc::sysctlbyname(
            cname.as_ptr(),
            &mut level as *mut i32 as *mut libc::c_void,
            &mut size,
            std::ptr::null_mut(),
            0,
        )
    };
    if status != 0 {
        return Pressure::Unknown;
    }
    match level {
        1 => Pressure::Normal,
        2 => Pressure::Warning,
        4 => Pressure::Critical,
        _ => Pressure::Unknown,
    }
}

#[cfg(not(target_os = "macos"))]
fn memory_pressure() -> Pressure {
    Pressure::Unknown
}

fn memory_bytes(system: &sysinfo::System) -> (u64, u64) {
    let total = system.total_memory();
    #[cfg(target_os = "macos")]
    let used = mac_memory_used(total).unwrap_or_else(|| system.used_memory());
    #[cfg(not(target_os = "macos"))]
    let used = system.used_memory();
    (used, total)
}

#[cfg(target_os = "macos")]
#[allow(deprecated)]
fn mac_memory_used(total: u64) -> Option<u64> {
    unsafe {
        let mut stats: libc::vm_statistics64 = std::mem::zeroed();
        let mut count = libc::HOST_VM_INFO64_COUNT;
        let status = libc::host_statistics64(
            libc::mach_host_self(),
            libc::HOST_VM_INFO64,
            &mut stats as *mut libc::vm_statistics64 as *mut i32,
            &mut count,
        );
        if status != libc::KERN_SUCCESS {
            return None;
        }
        let page_size = libc::sysconf(libc::_SC_PAGESIZE);
        if page_size <= 0 {
            return None;
        }
        let page = page_size as u64;
        let wired = u64::from(stats.wire_count) * page;
        let compressed = u64::from(stats.compressor_page_count) * page;
        let cached =
            (u64::from(stats.external_page_count) + u64::from(stats.purgeable_count)) * page;
        let app = (u64::from(stats.active_count)
            + u64::from(stats.inactive_count)
            + u64::from(stats.speculative_count))
            * page;
        let app = app.saturating_sub(cached);
        Some((app + wired + compressed).min(total))
    }
}
