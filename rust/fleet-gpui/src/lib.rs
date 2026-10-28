//! FleetConsole GPUI client.
//!
//! A desktop window over the same two feeds the terminal client reads: the
//! controller snapshot and this machine's telemetry, both owned by
//! `fleet-ui-core`'s background threads. Everything drawn comes from
//! `fleet_ui_core::views::Dashboard`, so this client and the terminal client
//! cannot disagree about a count, a threshold or an unavailable value. Actions
//! go only through `Controller::submit`; nothing here signals a process.
//!
//! The modules without GPUI types (`cli`, `state`, `geometry`, `logo`,
//! `feeds`, `verify`) hold the logic and carry the unit tests. The GPUI
//! modules (`app`, `ui`, `quick`, `full`, `status_item`) turn that state into
//! elements and route input back into it.

pub mod app;
pub mod cli;
pub mod feeds;
pub mod full;
pub mod geometry;
pub mod logo;
pub mod palette;
pub mod quick;
pub mod state;
pub mod status_item;
pub mod ui;
pub mod verify;

pub fn version() -> &'static str {
    env!("CARGO_PKG_VERSION")
}
