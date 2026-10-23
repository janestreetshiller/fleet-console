//! A measured snapshot or an explicit observation failure. Never substitutes data.

#[derive(Debug, PartialEq)]
pub struct SnapshotState<T> {
    observation: Result<T, String>,
}

impl<T> SnapshotState<T> {
    pub fn from_result<E: std::fmt::Display>(observation: Result<T, E>) -> Self {
        Self {
            observation: observation.map_err(|error| error.to_string()),
        }
    }

    pub fn snapshot(&self) -> Option<&T> {
        self.observation.as_ref().ok()
    }

    pub fn error(&self) -> Option<&str> {
        self.observation.as_ref().err().map(String::as_str)
    }

    pub fn record<E: std::fmt::Display>(&mut self, observation: Result<T, E>) {
        // A failed refresh must not leave an earlier sample looking current.
        self.observation = observation.map_err(|error| error.to_string());
    }
}

#[cfg(test)]
mod tests {
    use super::SnapshotState;

    #[test]
    fn measured_sample_is_preserved() {
        let state = SnapshotState::from_result(Ok::<_, &str>(vec![42, 73]));
        assert_eq!(state.snapshot(), Some(&vec![42, 73]));
        assert_eq!(state.error(), None);
    }

    #[test]
    fn failed_initial_sample_has_no_replacement_measurement() {
        let state = SnapshotState::<Vec<u32>>::from_result(Err("sensor unavailable"));
        assert_eq!(state.snapshot(), None);
        assert_eq!(state.error(), Some("sensor unavailable"));
    }

    #[test]
    fn failed_refresh_clears_previous_sample_and_can_recover() {
        let mut state = SnapshotState::from_result(Ok::<_, &str>(41));
        state.record(Err("collector disconnected"));
        assert_eq!(state.snapshot(), None);
        assert_eq!(state.error(), Some("collector disconnected"));
        state.record(Ok::<_, &str>(92));
        assert_eq!(state.snapshot(), Some(&92));
        assert_eq!(state.error(), None);
    }
}
