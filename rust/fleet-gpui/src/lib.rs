
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
