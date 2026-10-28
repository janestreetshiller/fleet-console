//! OS-agnostic telemetry provider and hardware capability abstraction.
//!
//! Abstracts system metric collection behind an OS-independent `TelemetryProvider`
//! trait, replacing macOS-exclusive assumptions with configurable hardware profiles.

use serde::{Deserialize, Serialize};
use std::fmt;

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub enum ThermalLevel {
    Nominal,
    Fair,
    Serious,
    Critical,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub enum CoreKind {
    Performance,
    Efficiency,
    Symmetric,
    Accelerator,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct CpuCluster {
    pub name: String,
    pub kind: CoreKind,
    pub logical_core_indices: Vec<usize>,
    pub base_clock_mhz: Option<u32>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct HardwareProfile {
    pub os_family: String,
    pub architecture: String,
    pub host_name: String,
    pub logical_cores: usize,
    pub physical_cores: usize,
    pub clusters: Vec<CpuCluster>,
    pub total_memory_bytes: u64,
    pub swap_total_bytes: u64,
    pub is_unified_memory: bool,
    pub has_hardware_thermal_sensor: bool,
}

impl Default for HardwareProfile {
    fn default() -> Self {
        Self {
            os_family: std::env::consts::OS.to_string(),
            architecture: std::env::consts::ARCH.to_string(),
            host_name: "fleet-node-01".to_string(),
            logical_cores: 8,
            physical_cores: 8,
            clusters: vec![CpuCluster {
                name: "Primary Cluster".to_string(),
                kind: CoreKind::Symmetric,
                logical_core_indices: (0..8).collect(),
                base_clock_mhz: Some(3200),
            }],
            total_memory_bytes: 32 * 1024 * 1024 * 1024,
            swap_total_bytes: 8 * 1024 * 1024 * 1024,
            is_unified_memory: cfg!(target_os = "macos"),
            has_hardware_thermal_sensor: true,
        }
    }
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct ProcessMetric {
    pub pid: u32,
    pub ppid: Option<u32>,
    pub name: String,
    pub exe_path: String,
    pub cpu_pct: f32,
    pub memory_rss_bytes: u64,
    pub memory_virtual_bytes: u64,
    pub status: String,
    pub start_time_seconds: u64,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct StoragePoolMetric {
    pub mount_point: String,
    pub filesystem: String,
    pub total_bytes: u64,
    pub available_bytes: u64,
    pub read_bytes_per_sec: u64,
    pub write_bytes_per_sec: u64,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct SocketEndpointMetric {
    pub protocol: String,
    pub local_addr: String,
    pub remote_addr: Option<String>,
    pub state: String,
    pub associated_pid: Option<u32>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum MemoryPoolType {
    SystemHeap,
    SharedMemoryPool,
    ContextWindowCache,
    GpuAllocated,
    PersistentMmap,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct MemoryPoolMetric {
    pub name: String,
    pub pool_type: MemoryPoolType,
    pub allocated_bytes: u64,
    pub capacity_bytes: Option<u64>,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct TelemetrySnapshot {
    pub timestamp_seconds: f64,
    pub cpu_usage_pct: f32,
    pub per_core_usage: Vec<f32>,
    pub used_memory_bytes: u64,
    pub total_memory_bytes: u64,
    pub used_swap_bytes: u64,
    pub thermal_level: ThermalLevel,
    pub processes: Vec<ProcessMetric>,
    pub storage_pools: Vec<StoragePoolMetric>,
    pub socket_endpoints: Vec<SocketEndpointMetric>,
    pub memory_pools: Vec<MemoryPoolMetric>,
}

#[derive(Debug, Clone)]
pub enum TelemetryError {
    SamplingError(String),
    HardwareQueryError(String),
    PlatformUnsupported(String),
}

impl fmt::Display for TelemetryError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::SamplingError(msg) => write!(f, "Telemetry sampling error: {msg}"),
            Self::HardwareQueryError(msg) => write!(f, "Hardware query error: {msg}"),
            Self::PlatformUnsupported(msg) => write!(f, "Platform unsupported: {msg}"),
        }
    }
}

impl std::error::Error for TelemetryError {}

/// Abstract, cross-platform telemetry provider.
pub trait TelemetryProvider: Send + Sync {
    fn hardware_profile(&self) -> &HardwareProfile;
    fn sample(&mut self) -> Result<TelemetrySnapshot, TelemetryError>;
    fn refresh(&mut self) -> Result<(), TelemetryError>;
}

/// Portable telemetry provider backed by `sysinfo`.
pub struct SysinfoTelemetryProvider {
    profile: HardwareProfile,
    sys: sysinfo::System,
    disks: sysinfo::Disks,
    networks: sysinfo::Networks,
    last_sample_instant: Option<std::time::Instant>,
}

impl SysinfoTelemetryProvider {
    pub fn new() -> Self {
        let mut sys = sysinfo::System::new_all();
        sys.refresh_all();
        let disks = sysinfo::Disks::new_with_refreshed_list();
        let networks = sysinfo::Networks::new_with_refreshed_list();

        let logical_cores = sys.cpus().len().max(1);
        let physical_cores = sys.physical_core_count().unwrap_or(logical_cores);

        let clusters = vec![CpuCluster {
            name: "Default Cores".to_string(),
            kind: CoreKind::Symmetric,
            logical_core_indices: (0..logical_cores).collect(),
            base_clock_mhz: sys.cpus().first().map(|c| c.frequency() as u32),
        }];

        let profile = HardwareProfile {
            os_family: sysinfo::System::name().unwrap_or_else(|| std::env::consts::OS.to_string()),
            architecture: std::env::consts::ARCH.to_string(),
            host_name: sysinfo::System::host_name().unwrap_or_else(|| "fleet-node".to_string()),
            logical_cores,
            physical_cores,
            clusters,
            total_memory_bytes: sys.total_memory(),
            swap_total_bytes: sys.total_swap(),
            is_unified_memory: cfg!(target_os = "macos"),
            has_hardware_thermal_sensor: true,
        };

        Self {
            profile,
            sys,
            disks,
            networks,
            last_sample_instant: Some(std::time::Instant::now()),
        }
    }
}

impl Default for SysinfoTelemetryProvider {
    fn default() -> Self {
        Self::new()
    }
}

impl TelemetryProvider for SysinfoTelemetryProvider {
    fn hardware_profile(&self) -> &HardwareProfile {
        &self.profile
    }

    fn refresh(&mut self) -> Result<(), TelemetryError> {
        self.sys.refresh_all();
        self.disks.refresh();
        self.networks.refresh();
        self.last_sample_instant = Some(std::time::Instant::now());
        Ok(())
    }

    fn sample(&mut self) -> Result<TelemetrySnapshot, TelemetryError> {
        self.refresh()?;

        let now_sec = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .unwrap_or_default()
            .as_secs_f64();

        let global_cpu = self.sys.global_cpu_usage();
        let per_core_usage: Vec<f32> = self.sys.cpus().iter().map(|c| c.cpu_usage()).collect();

        let mut processes = Vec::new();
        for (pid, proc) in self.sys.processes() {
            processes.push(ProcessMetric {
                pid: pid.as_u32(),
                ppid: proc.parent().map(|p| p.as_u32()),
                name: proc.name().to_string_lossy().to_string(),
                exe_path: proc
                    .exe()
                    .map(|p| p.to_string_lossy().to_string())
                    .unwrap_or_default(),
                cpu_pct: proc.cpu_usage(),
                memory_rss_bytes: proc.memory(),
                memory_virtual_bytes: proc.virtual_memory(),
                status: format!("{:?}", proc.status()),
                start_time_seconds: proc.start_time(),
            });
        }

        let mut storage_pools = Vec::new();
        for disk in &self.disks {
            storage_pools.push(StoragePoolMetric {
                mount_point: disk.mount_point().to_string_lossy().to_string(),
                filesystem: disk.file_system().to_string_lossy().to_string(),
                total_bytes: disk.total_space(),
                available_bytes: disk.available_space(),
                read_bytes_per_sec: 0,
                write_bytes_per_sec: 0,
            });
        }

        let memory_pools = vec![
            MemoryPoolMetric {
                name: "Host System Heap".to_string(),
                pool_type: MemoryPoolType::SystemHeap,
                allocated_bytes: self.sys.used_memory(),
                capacity_bytes: Some(self.sys.total_memory()),
            },
            MemoryPoolMetric {
                name: "Swap File Space".to_string(),
                pool_type: MemoryPoolType::PersistentMmap,
                allocated_bytes: self.sys.used_swap(),
                capacity_bytes: Some(self.sys.total_swap()),
            },
        ];

        let thermal_level = if global_cpu > 90.0 {
            ThermalLevel::Serious
        } else if global_cpu > 70.0 {
            ThermalLevel::Fair
        } else {
            ThermalLevel::Nominal
        };

        Ok(TelemetrySnapshot {
            timestamp_seconds: now_sec,
            cpu_usage_pct: global_cpu,
            per_core_usage,
            used_memory_bytes: self.sys.used_memory(),
            total_memory_bytes: self.sys.total_memory(),
            used_swap_bytes: self.sys.used_swap(),
            thermal_level,
            processes,
            storage_pools,
            socket_endpoints: Vec::new(),
            memory_pools,
        })
    }
}

/// Deterministic mock telemetry provider for tests and simulation.
pub struct SimulatedTelemetryProvider {
    pub profile: HardwareProfile,
    pub current_snapshot: TelemetrySnapshot,
}

impl SimulatedTelemetryProvider {
    pub fn new() -> Self {
        let profile = HardwareProfile::default();
        let current_snapshot = TelemetrySnapshot {
            timestamp_seconds: 1770000000.0,
            cpu_usage_pct: 24.5,
            per_core_usage: vec![30.0, 20.0, 15.0, 35.0, 22.0, 18.0, 26.0, 30.0],
            used_memory_bytes: 14 * 1024 * 1024 * 1024,
            total_memory_bytes: 32 * 1024 * 1024 * 1024,
            used_swap_bytes: 512 * 1024 * 1024,
            thermal_level: ThermalLevel::Nominal,
            processes: vec![
                ProcessMetric {
                    pid: 1001,
                    ppid: Some(1),
                    name: "ouros-x".to_string(),
                    exe_path: "/Applications/Ouros X.app/Contents/MacOS/ouros-x".to_string(),
                    cpu_pct: 12.4,
                    memory_rss_bytes: 850 * 1024 * 1024,
                    memory_virtual_bytes: 2048 * 1024 * 1024,
                    status: "Running".to_string(),
                    start_time_seconds: 1769990000,
                },
                ProcessMetric {
                    pid: 1002,
                    ppid: Some(1001),
                    name: "codex-agent".to_string(),
                    exe_path: "/usr/local/bin/codex-agent".to_string(),
                    cpu_pct: 8.2,
                    memory_rss_bytes: 420 * 1024 * 1024,
                    memory_virtual_bytes: 1024 * 1024 * 1024,
                    status: "Running".to_string(),
                    start_time_seconds: 1769992000,
                },
                ProcessMetric {
                    pid: 1003,
                    ppid: Some(1),
                    name: "WindowServer".to_string(),
                    exe_path: "/System/Library/CoreServices/WindowServer".to_string(),
                    cpu_pct: 6.0,
                    memory_rss_bytes: 680 * 1024 * 1024,
                    memory_virtual_bytes: 3000 * 1024 * 1024,
                    status: "Running".to_string(),
                    start_time_seconds: 1769980000,
                },
                ProcessMetric {
                    pid: 1004,
                    ppid: Some(1),
                    name: "swift-frontend".to_string(),
                    exe_path: "/usr/bin/swift-frontend".to_string(),
                    cpu_pct: 95.5,
                    memory_rss_bytes: 2200 * 1024 * 1024,
                    memory_virtual_bytes: 4096 * 1024 * 1024,
                    status: "Running".to_string(),
                    start_time_seconds: 1769999000,
                },
            ],
            storage_pools: vec![
                StoragePoolMetric {
                    mount_point: "/".to_string(),
                    filesystem: "apfs".to_string(),
                    total_bytes: 994 * 1024 * 1024 * 1024,
                    available_bytes: 142 * 1024 * 1024 * 1024,
                    read_bytes_per_sec: 12 * 1024 * 1024,
                    write_bytes_per_sec: 45 * 1024 * 1024,
                },
                StoragePoolMetric {
                    mount_point: "/System/Volumes/Data".to_string(),
                    filesystem: "apfs".to_string(),
                    total_bytes: 994 * 1024 * 1024 * 1024,
                    available_bytes: 142 * 1024 * 1024 * 1024,
                    read_bytes_per_sec: 4 * 1024 * 1024,
                    write_bytes_per_sec: 8 * 1024 * 1024,
                },
            ],
            socket_endpoints: vec![
                SocketEndpointMetric {
                    protocol: "tcp".to_string(),
                    local_addr: "127.0.0.1:50139".to_string(),
                    remote_addr: Some("127.0.0.1:60165".to_string()),
                    state: "ESTABLISHED".to_string(),
                    associated_pid: Some(1001),
                },
                SocketEndpointMetric {
                    protocol: "unix".to_string(),
                    local_addr: "/var/run/fleetd.sock".to_string(),
                    remote_addr: None,
                    state: "LISTENING".to_string(),
                    associated_pid: Some(1001),
                },
            ],
            memory_pools: vec![
                MemoryPoolMetric {
                    name: "System Unified RAM".to_string(),
                    pool_type: MemoryPoolType::SystemHeap,
                    allocated_bytes: 14 * 1024 * 1024 * 1024,
                    capacity_bytes: Some(32 * 1024 * 1024 * 1024),
                },
                MemoryPoolMetric {
                    name: "Ouros Context Window Buffer".to_string(),
                    pool_type: MemoryPoolType::ContextWindowCache,
                    allocated_bytes: 384 * 1024 * 1024,
                    capacity_bytes: Some(1024 * 1024 * 1024),
                },
                MemoryPoolMetric {
                    name: "Metal GPU Render Pool".to_string(),
                    pool_type: MemoryPoolType::GpuAllocated,
                    allocated_bytes: 1280 * 1024 * 1024,
                    capacity_bytes: Some(8192 * 1024 * 1024),
                },
            ],
        };

        Self {
            profile,
            current_snapshot,
        }
    }
}

impl Default for SimulatedTelemetryProvider {
    fn default() -> Self {
        Self::new()
    }
}

impl TelemetryProvider for SimulatedTelemetryProvider {
    fn hardware_profile(&self) -> &HardwareProfile {
        &self.profile
    }

    fn refresh(&mut self) -> Result<(), TelemetryError> {
        self.current_snapshot.timestamp_seconds += 1.0;
        Ok(())
    }

    fn sample(&mut self) -> Result<TelemetrySnapshot, TelemetryError> {
        self.refresh()?;
        Ok(self.current_snapshot.clone())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_simulated_telemetry() {
        let mut provider = SimulatedTelemetryProvider::new();
        assert_eq!(provider.hardware_profile().logical_cores, 8);
        let sample = provider.sample().expect("sample failed");
        assert_eq!(sample.processes.len(), 4);
        assert_eq!(sample.storage_pools.len(), 2);
        assert_eq!(sample.socket_endpoints.len(), 2);
    }
}
