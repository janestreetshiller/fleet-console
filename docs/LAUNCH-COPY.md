# FleetConsole launch copy

## What these tools do

**FleetConsole:** See what is using your Mac and why background jobs are running.
Check CPU, memory, storage and network use from the menu bar, then open the
dashboard to inspect a process, its owner, its logs and its health evidence.
For jobs started through FleetConsole's controller, you can pause, resume, renew
their time limit, restart or stop them.

**fleetctl:** Give your scripts and coding agents the same service controls from
the terminal. Start a job with a name, owner, purpose and lease; inspect its logs
and events; renew it while needed; stop it when finished. It is bundled with
FleetConsole and talks to the local controller. Claiming an existing job records
it without giving the controller permission to stop it.

FleetConsole is the visual console; fleetctl is its command-line client; fleetd
is the controller that starts and supervises services. The Rust `fleet-agent`
helper and FleetConsole's account-backed Ouros Agent review are separate from
Agent-RX, the terminal coding agent. Do not label all three as the same agent.

## Site cards

| Name | One-line description | Action |
| --- | --- | --- |
| FleetConsole | Understand your Mac's load and manage the background jobs your coding agents start. | View FleetConsole |
| fleetctl | Start, inspect and stop named background jobs from scripts or the terminal. | Read the CLI guide |

Link fleetctl to [the CLI guide](CLI.md), not a separate installer. Link the app
to a verified downloadable release. Main-source features and an installed
development build do not prove that the public download contains those features.

## Short post

FleetConsole is a free macOS app for keeping an eye on your Mac and the background work your coding agents start. Quick View has CPU and memory dials, a disk-capacity map and upload/download bars. Open the dashboard for charts, processes and service logs. The whole app is MIT licensed; optional multi-device access uses Ouros (operated by Ouros AI, LLC) at $10/month.

Download: https://github.com/janestreetshiller/fleet-console/releases/latest
Source: https://github.com/janestreetshiller/fleet-console

## Release announcement

FleetConsole keeps CPU, memory and disk-capacity meters in your menu bar. Open
Quick View for resource dials and upload/download bars. The compact
header opens the dashboard, an Agent investigation menu, and configuration links.
Operations groups service, network, agent and account tools in the dashboard.

Name and color-tag services so you can recognize them. Register agent IDs, see detected sessions and handle requests without turning the menu into a resource table. The dashboard opens to a contained overview, with a sidebar you can tuck away when you want more room for the charts.

Launch background work through `fleetctl` with an owner, purpose and lease. Renew what you still need; the controller cleans up unpaused services it launched when their leases expire. Paused services keep their processes and resources until resumed. Claiming an existing process adds visibility, not permission to stop it.

Local monitoring and service management are free. The complete source — core, controller, CLI, Rust protocol and native app — is published under MIT. Optional multi-device access costs $10 USD/month through Ouros (Ouros AI, LLC) and uses your existing SSH setup for remote metrics and read-only service inventory. AI credits and automatic repairs are not included.

Download: https://github.com/janestreetshiller/fleet-console/releases/latest

## Publication notes

Use the shipping build number and verified release link from the release notes.
Publish only reviewed captures from that build. The source is MIT licensed;
check repository visibility and the downloadable artifact separately. Do not
call disk capacity a temperature reading, promise autonomous repairs, or imply
a donation checkout exists. Keep the prior privately supplied soundtrack out of
public exports unless master and synchronization permissions are documented.

Memory safety and low latency are engineering goals. Describe measured results
with their workload and build identity. A Rust or GPUI label alone proves neither
a whole-application safety property nor an interaction-latency improvement.
