//! `fleet-gpui`: the FleetConsole desktop client. See `--help`.

use fleet_gpui::cli::{self, Command};

fn main() {
    let args: Vec<String> = std::env::args().skip(1).collect();
    let command = match cli::parse(args.iter().map(String::as_str)) {
        Ok(command) => command,
        Err(error) => {
            eprintln!("fleet-gpui: {error}");
            std::process::exit(2);
        }
    };
    match command {
        Command::Help => print!("{}", cli::usage()),
        Command::Version => println!("fleet-gpui {}", fleet_gpui::version()),
        Command::Identity => println!("{}", fleet_gpui::verify::identity()),
        Command::Verify(options) => {
            let report = fleet_gpui::verify::run(&options);
            println!(
                "{}",
                serde_json::to_string_pretty(&report).unwrap_or_else(|_| report.to_string())
            );
        }
        Command::Run(options) => fleet_gpui::app::run(*options),
    }
}
