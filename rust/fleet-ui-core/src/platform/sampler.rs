//! `sysinfo`-backed sampling shared by macOS and Linux.

use super::{os, HostSample, ProcessRow, Volume, MAX_PROCESSES, MAX_VOLUMES};
use crate::observe::{Metric, Reason};
use std::time::{Instant, SystemTime};
use sysinfo::{Disks, Networks, ProcessRefreshKind, ProcessesToUpdate, System};

pub struct Sampler {
    system: System,
    disks: Disks,
    networks: Networks,
    last_network: Option<Instant>,
    samples: u64,
}

impl Default for Sampler {
    fn default() -> Self {
        Self::new()
    }
}

impl Sampler {
    pub fn new() -> Self {
        Self {
            system: System::new(),
            disks: Disks::new_with_refreshed_list(),
            networks: Networks::new_with_refreshed_list(),
            last_network: None,
            samples: 0,
        }
    }

    pub fn sample(&mut self) -> HostSample {
        let taken_at = SystemTime::now();
        self.system.refresh_cpu_usage();
        self.system.refresh_memory();
        self.system.refresh_processes_specifics(
            ProcessesToUpdate::All,
            ProcessRefreshKind::new().with_cpu().with_memory(),
        );
        self.disks.refresh();
        let now = Instant::now();
        self.networks.refresh();
        let elapsed = self
            .last_network
            .map(|t| now.duration_since(t).as_secs_f64());
        self.last_network = Some(now);
        self.samples += 1;

        // CPU use is a difference between two readings; the first has none.
        let first = self.samples == 1;
        let cpu_pct = if first {
            Metric::Unavailable(Reason::AwaitingSample)
        } else {
            Metric::from_option(
                Some(f64::from(self.system.global_cpu_usage())),
                Reason::Failed,
            )
        };

        let total = self.system.total_memory();
        let used = self.system.used_memory();
        let (memory_pct, memory_used_bytes, memory_total_bytes) = if total > 0 {
            (
                Metric::Measured(used as f64 / total as f64 * 100.0),
                Some(used),
                Some(total),
            )
        } else {
            (Metric::Unavailable(Reason::Failed), None, None)
        };

        let (rx, tx) = self.network_rates(elapsed);

        let mut volumes: Vec<Volume> = self
            .disks
            .list()
            .iter()
            .map(|d| Volume {
                mount: d.mount_point().to_string_lossy().into_owned(),
                filesystem: d.file_system().to_string_lossy().into_owned(),
                total_bytes: d.total_space(),
                available_bytes: d.available_space(),
                removable: d.is_removable(),
            })
            .filter(|v| v.total_bytes > 0 && os::is_user_volume(&v.mount, &v.filesystem))
            .collect();
        volumes.sort_by_key(|v| std::cmp::Reverse(v.total_bytes));
        volumes.truncate(MAX_VOLUMES);
        let disk = os::primary_volume(&volumes).cloned();
        let disk_pct = disk
            .as_ref()
            .map(Volume::used_percent)
            .unwrap_or(Metric::Unavailable(Reason::Failed));

        let mut processes: Vec<ProcessRow> = self
            .system
            .processes()
            .iter()
            .map(|(pid, p)| ProcessRow {
                pid: pid.as_u32(),
                ppid: p.parent().map(|pp| pp.as_u32()),
                name: p.name().to_string_lossy().into_owned(),
                cpu_pct: if first {
                    Metric::Unavailable(Reason::AwaitingSample)
                } else {
                    Metric::Measured(f64::from(p.cpu_usage()))
                },
                rss_bytes: p.memory(),
                start_time: p.start_time(),
            })
            .collect();
        let process_count = processes.len();
        processes.sort_by(|a, b| {
            let (ca, cb) = (
                a.cpu_pct.value().unwrap_or(0.0),
                b.cpu_pct.value().unwrap_or(0.0),
            );
            cb.total_cmp(&ca).then(b.rss_bytes.cmp(&a.rss_bytes))
        });
        processes.truncate(MAX_PROCESSES);

        HostSample {
            taken_at,
            os: std::env::consts::OS,
            cpu_pct,
            memory_pct,
            memory_used_bytes,
            memory_total_bytes,
            swap_used_bytes: Some(self.system.used_swap()),
            disk_pct,
            disk,
            net_rx_bytes_per_sec: rx,
            net_tx_bytes_per_sec: tx,
            gpu_pct: os::gpu_busy_percent(),
            uptime_sec: Some(System::uptime()),
            process_count,
            processes,
            volumes,
            cpu_history: Vec::new(),
            rx_history: Vec::new(),
            tx_history: Vec::new(),
        }
    }

    fn network_rates(&self, elapsed: Option<f64>) -> (Metric, Metric) {
        let Some(seconds) = elapsed.filter(|s| *s > 0.0) else {
            let waiting = Metric::Unavailable(Reason::AwaitingSample);
            return (waiting, waiting);
        };
        let mut rx = 0u64;
        let mut tx = 0u64;
        let mut links = 0;
        for (name, data) in self.networks.list() {
            if !os::is_physical_interface(name) {
                continue;
            }
            links += 1;
            rx = rx.saturating_add(data.received());
            tx = tx.saturating_add(data.transmitted());
        }
        if links == 0 {
            // No physical link is a fact worth showing, not a zero rate.
            let none = Metric::Unavailable(Reason::NotMeasured);
            return (none, none);
        }
        (
            Metric::Measured(rx as f64 / seconds),
            Metric::Measured(tx as f64 / seconds),
        )
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn first_sample_marks_differences_as_awaiting() {
        let mut sampler = Sampler::new();
        let first = sampler.sample();
        assert_eq!(first.cpu_pct, Metric::Unavailable(Reason::AwaitingSample));
        assert_eq!(
            first.net_rx_bytes_per_sec.reason(),
            Some(Reason::AwaitingSample)
        );
        assert!(first.memory_pct.is_measured());
        assert!(first.process_count > 0);
        assert!(first.processes.len() <= MAX_PROCESSES);
        std::thread::sleep(sysinfo::MINIMUM_CPU_UPDATE_INTERVAL);
        let second = sampler.sample();
        assert!(second.cpu_pct.is_measured());
    }
}
