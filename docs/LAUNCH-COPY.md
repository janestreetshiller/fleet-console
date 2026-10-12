# FleetConsole launch copy

## Short post

FleetConsole is a free macOS app for keeping an eye on your Mac and the background work your coding agents start. Quick View has CPU and memory dials, a disk-capacity map and upload/download bars. Open the dashboard for charts, processes and service logs. The whole app is MIT licensed; optional multi-device access uses Ouros (operated by Ouros AI, LLC) at $10/month.

Download: https://github.com/janestreetshiller/fleet-console/releases/latest
Source: https://github.com/janestreetshiller/fleet-console

## Release announcement

FleetConsole puts four instruments in your menu bar: CPU, memory, disk capacity and network traffic. The five tabs share one compact frame, with configuration on the left, refresh on the right and a dashboard action below.

Name and color-tag services so you can recognize them. Register agent IDs, see detected sessions and handle requests without turning the menu into a resource table. The dashboard opens to a contained overview, with a sidebar you can tuck away when you want more room for the charts.

Launch background work through `fleetctl` with an owner, purpose and lease. Renew what you still need; the controller cleans up unpaused services it launched when their leases expire. Paused services keep their processes and resources until resumed. Claiming an existing process adds visibility, not permission to stop it.

Local monitoring and service management are free. The complete source — core, controller, CLI, Rust protocol and native app — is published under MIT. Optional multi-device access costs $10 USD/month through Ouros (Ouros AI, LLC) and uses your existing SSH setup for remote metrics and read-only service inventory. AI credits and automatic repairs are not included.

Download: https://github.com/janestreetshiller/fleet-console/releases/latest

## Publication notes

Use the shipping build number and verified release link from the release notes. Publish only reviewed captures from the current native views. Do not describe the whole app as open source, call disk capacity a temperature reading, promise autonomous repairs, or imply a donation checkout exists. Keep the prior privately supplied soundtrack out of public exports unless master and synchronization permissions are documented.
