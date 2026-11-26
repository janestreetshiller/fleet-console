use serde::de::{self, value::MapAccessDeserializer};
use serde::{Deserialize, Deserializer, Serialize};
use std::fmt;
use std::fs::{self, DirBuilder, OpenOptions};
use std::io::{self, Write};
use std::os::unix::fs::{DirBuilderExt, OpenOptionsExt};
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicUsize, Ordering};
use std::time::Duration;

static NEXT_TEMP: AtomicUsize = AtomicUsize::new(0);

pub(crate) struct ConfigPath {
    file: PathBuf,
    logs: PathBuf,
}

impl ConfigPath {
    pub(crate) fn detect() -> Self {
        if let Some(root) = std::env::var_os(fleet_proto::STATE_ROOT_VARIABLE).filter(|v| !v.is_empty()) {
            return Self::library(Path::new(&root));
        }
        let home = std::env::home_dir().unwrap_or_default();
        if cfg!(target_os = "macos") {
            return Self::library(&home);
        }
        let state = std::env::var_os("XDG_STATE_HOME")
            .filter(|v| !v.is_empty())
            .map_or_else(|| home.join(".local/state"), PathBuf::from)
            .join("fleetconsole");
        Self {
            file: state.join("config.json"),
            logs: state.join("logs"),
        }
    }

    fn library(root: &Path) -> Self {
        Self {
            file: root.join("Library/Application Support/FleetConsole/config.json"),
            logs: root.join("Library/Logs/FleetConsole"),
        }
    }

    pub(crate) fn file(&self) -> &Path {
        &self.file
    }

    pub(crate) fn logs(&self) -> &Path {
        &self.logs
    }

    pub(crate) fn ensure_exists(&self) -> io::Result<()> {
        match fs::symlink_metadata(&self.file) {
            Ok(_) => return Ok(()),
            Err(error) if error.kind() == io::ErrorKind::NotFound => {}
            Err(error) => return Err(error),
        }
        let directory = self.file.parent().expect("config path has a parent");
        DirBuilder::new().recursive(true).mode(0o700).create(directory)?;
        let (temporary, mut file) = loop {
            let temporary = directory.join(format!(
                ".config-{}-{}.tmp",
                std::process::id(),
                NEXT_TEMP.fetch_add(1, Ordering::Relaxed),
            ));
            match OpenOptions::new().write(true).create_new(true).mode(0o600).open(&temporary) {
                Ok(file) => break (temporary, file),
                Err(error) if error.kind() == io::ErrorKind::AlreadyExists => continue,
                Err(error) => return Err(error),
            }
        };
        let result = (|| {
            let name = sysinfo::System::host_name();
            let mut bytes = serde_json::to_vec_pretty(&InitialConfig {
                devices: [InitialDevice {
                    id: "self",
                    name: name.as_deref().unwrap_or("This Mac"),
                    local_host: "localhost",
                    is_self: true,
                }],
            })?;
            bytes.push(b'\n');
            file.write_all(&bytes)?;
            file.sync_all()?;
            match fs::hard_link(&temporary, &self.file) {
                Err(error) if error.kind() == io::ErrorKind::AlreadyExists => Ok(()),
                result => result,
            }
        })();
        result.and(fs::remove_file(temporary))
    }
}

#[derive(Serialize)]
struct InitialConfig<'a> {
    devices: [InitialDevice<'a>; 1],
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct InitialDevice<'a> {
    id: &'a str,
    name: &'a str,
    local_host: &'a str,
    is_self: bool,
}

#[derive(Clone, Debug, Default, PartialEq)]
pub(crate) struct ConfigRead {
    pub config: UiConfig,
    pub error: Option<String>,
}

impl ConfigRead {
    fn unreadable(error: impl fmt::Display) -> Self {
        Self {
            config: UiConfig::default(),
            error: Some(format!("config.json unreadable ({error}); using defaults")),
        }
    }
}

#[derive(Clone, Debug, PartialEq)]
pub(crate) struct UiConfig {
    pub sections: Sections,
    pub process_sample: Duration,
    pub network_refresh: Duration,
}

impl Default for UiConfig {
    fn default() -> Self {
        Self {
            sections: Sections::default(),
            process_sample: Duration::from_secs(4),
            network_refresh: Duration::from_secs(20),
        }
    }
}

impl UiConfig {
    pub(crate) fn load(path: &Path) -> ConfigRead {
        let bytes = match fs::read(path) {
            Ok(bytes) => bytes,
            Err(error) if error.kind() == io::ErrorKind::NotFound => return ConfigRead::default(),
            Err(error) => return ConfigRead::unreadable(error),
        };
        let Object(config) = match serde_json::from_slice::<Object<ConfigFile>>(&bytes) {
            Ok(config) => config,
            Err(error) => return ConfigRead::unreadable(error),
        };
        let Some(Object(ui)) = config.ui else {
            return ConfigRead::default();
        };
        let mut config = Self::default();
        if let Some(Object(sections)) = ui.sections {
            config.sections = sections;
        }
        if let Some(Object(intervals)) = ui.intervals {
            if let Some(seconds) = intervals.process_sample_sec {
                let Ok(interval) = Duration::try_from_secs_f64(seconds.max(2.0)) else {
                    return ConfigRead::unreadable("ui.intervals.processSampleSec is too large");
                };
                config.process_sample = interval;
            }
            if let Some(seconds) = intervals.network_refresh_sec {
                let Ok(interval) = Duration::try_from_secs_f64(seconds.max(5.0)) else {
                    return ConfigRead::unreadable("ui.intervals.networkRefreshSec is too large");
                };
                config.network_refresh = interval;
            }
        }
        ConfigRead { config, error: None }
    }
}

#[derive(Clone, Debug, Deserialize, PartialEq)]
#[serde(default)]
pub(crate) struct Sections {
    #[serde(deserialize_with = "section_enabled")]
    pub services: bool,
    #[serde(deserialize_with = "section_enabled")]
    pub agents: bool,
    #[serde(deserialize_with = "section_enabled")]
    pub processes: bool,
    #[serde(deserialize_with = "section_enabled")]
    pub network: bool,
    #[serde(deserialize_with = "section_enabled")]
    pub devices: bool,
    #[serde(deserialize_with = "section_enabled")]
    pub listening: bool,
}

impl Default for Sections {
    fn default() -> Self {
        Self {
            services: true,
            agents: true,
            processes: true,
            network: true,
            devices: true,
            listening: true,
        }
    }
}

fn section_enabled<'de, D: Deserializer<'de>>(deserializer: D) -> Result<bool, D::Error> {
    Ok(Option::<bool>::deserialize(deserializer)?.unwrap_or(true))
}

#[derive(Deserialize)]
struct ConfigFile {
    ui: Option<Object<UiFile>>,
}

#[derive(Deserialize)]
struct UiFile {
    sections: Option<Object<Sections>>,
    intervals: Option<Object<Intervals>>,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct Intervals {
    process_sample_sec: Option<f64>,
    network_refresh_sec: Option<f64>,
}

struct Object<T>(T);

impl<'de, T: Deserialize<'de>> Deserialize<'de> for Object<T> {
    fn deserialize<D: Deserializer<'de>>(deserializer: D) -> Result<Self, D::Error> {
        struct ObjectVisitor<T>(std::marker::PhantomData<T>);

        impl<'de, T: Deserialize<'de>> de::Visitor<'de> for ObjectVisitor<T> {
            type Value = Object<T>;

            fn expecting(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
                formatter.write_str("a JSON object")
            }

            fn visit_map<A: de::MapAccess<'de>>(self, map: A) -> Result<Self::Value, A::Error> {
                T::deserialize(MapAccessDeserializer::new(map)).map(Object)
            }
        }

        deserializer.deserialize_map(ObjectVisitor(std::marker::PhantomData))
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::os::unix::fs::PermissionsExt;

    struct TestDirectory(PathBuf);

    impl TestDirectory {
        fn new() -> Self {
            let path = std::env::temp_dir().join(format!(
                "fleet-console-config-{}-{}",
                std::process::id(),
                NEXT_TEMP.fetch_add(1, Ordering::Relaxed),
            ));
            DirBuilder::new().mode(0o700).create(&path).unwrap();
            Self(path)
        }
    }

    impl Drop for TestDirectory {
        fn drop(&mut self) {
            let _ = fs::remove_dir_all(&self.0);
        }
    }

    #[test]
    fn load_defaults_clamps_intervals_and_rejects_invalid_config() {
        let directory = TestDirectory::new();
        let file = directory.0.join("config.json");
        let defaults = UiConfig::load(&file);
        assert_eq!(defaults.error, None);
        assert_eq!(defaults.config.process_sample, Duration::from_secs(4));
        assert_eq!(defaults.config.network_refresh, Duration::from_secs(20));
        assert_eq!(defaults.config.sections, Sections {
            services: true,
            agents: true,
            processes: true,
            network: true,
            devices: true,
            listening: true,
        });

        fs::write(&file, br#"{
            "ui": {
                "sections": {"agents": false, "network": null, "listening": false},
                "intervals": {"processSampleSec": 0.25, "networkRefreshSec": -1}
            },
            "devices": [{"id": "peer"}]
        }"#).unwrap();
        let read = UiConfig::load(&file);
        assert_eq!(read.error, None);
        assert_eq!(read.config.process_sample, Duration::from_secs(2));
        assert_eq!(read.config.network_refresh, Duration::from_secs(5));
        assert_eq!(read.config.sections, Sections {
            agents: false,
            listening: false,
            ..defaults.config.sections.clone()
        });

        for invalid in [
            "{",
            "[]",
            r#"{"ui":{"sections":[],"intervals":null}}"#,
            r#"{"ui":{"sections":{"services":"false"}}}"#,
            r#"{"ui":{"intervals":{"processSampleSec":1e100}}}"#,
        ] {
            fs::write(&file, invalid).unwrap();
            let read = UiConfig::load(&file);
            assert_eq!(read.config, defaults.config);
            assert!(read.error.is_some());
        }
    }

    #[test]
    fn create_publishes_private_self_defaults_without_replacing_config() {
        let directory = TestDirectory::new();
        let path = ConfigPath::library(&directory.0);
        assert_eq!(path.file(), directory.0.join("Library/Application Support/FleetConsole/config.json"));
        assert_eq!(path.logs(), directory.0.join("Library/Logs/FleetConsole"));
        std::thread::scope(|scope| {
            let other = scope.spawn(|| path.ensure_exists());
            path.ensure_exists().unwrap();
            other.join().unwrap().unwrap();
        });
        let support = path.file().parent().unwrap();
        assert_eq!(fs::metadata(support).unwrap().permissions().mode() & 0o777, 0o700);
        assert_eq!(fs::metadata(path.file()).unwrap().permissions().mode() & 0o777, 0o600);
        assert_eq!(fs::read_dir(support).unwrap().count(), 1);
        let initial = fs::read(path.file()).unwrap();
        let json: serde_json::Value = serde_json::from_slice(&initial).unwrap();
        let devices = json["devices"].as_array().unwrap();
        assert_eq!(devices.len(), 1);
        assert_eq!(devices[0]["id"].as_str(), Some("self"));
        assert_eq!(devices[0]["isSelf"].as_bool(), Some(true));
        assert_eq!(devices[0]["localHost"].as_str(), Some("localhost"));
        assert_eq!(UiConfig::load(path.file()), ConfigRead::default());

        for existing in [r#"{"devices":[{"id":"peer"}],"unrelated":{"value":3}}"#, "{"] {
            fs::write(path.file(), existing).unwrap();
            path.ensure_exists().unwrap();
            assert_eq!(fs::read(path.file()).unwrap(), existing.as_bytes());
        }
    }
}
