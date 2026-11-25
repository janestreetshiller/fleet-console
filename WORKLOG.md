# FleetConsole source handoff — 2026-11-11

## Canonical recovery
- Main baseline: `f0d4aec`. Source integration preserves all original branches, stashes, worktrees, apps and controllers.
- Awareness `4015c0e`, consolidated `c2f3b5f`, directory `5e769fe` and hierarchy `4841d24` are represented by accepted main integrations `c4fb95c`, `3254ed2`, `31db7f6` and `3d1d33e`.
- Captured hierarchy `fc66fb0` and directory `42bd78d` match accepted source; current awareness navigation and managed-work rows replace the old Monitor/Background layout.
- Delivery `b8bf4ae`/`858e78d` supplies missing prebuilt preparation/verification, predecessor/core refusal, compiled identity, receipt digest checks, updater rollback and primary-action render/click behavior.
- Recovery snapshots `518d639`/`b6b2edf` equal their parents already on main. Current core1.1.13/product identity replaces historical core1.1.2/release1.3.1 stamps.

## Executed parent checks
- Core-update Python7 and release-policy fixtures passed; shell syntax passed.
- Native DesignCore suite5 passed: four actual light/dark enabled/disabled pixel captures, real button activation and disabled behavior.
- Window fixtures now use Apple's window-capable accessory policy; pixel and lifecycle assertions remain intact.
- Compiled app identity: core1.1.13, source SHA256 `8a9900dbbfe1d771b173ee7457d028136640336ff040a96ba0878d2e6f9d1ac1`, signal#F17B33, fill#B8460A, ink#FFFFFF.
- Terminal persistence uses a private `fleet-test-<UUID>` tmux socket. After Dock recovery, the actual Aqua `TerminalAgentSessionTests/durableShell` passed in58.056s: an exported shell variable and running background job survived window close and a new panel.
- Initial SSH/Aqua samples stopped in NSApplication/SkyLight IPC. User authorized GUI recovery; Dock restart succeeded and the native AppKit probe initialized. Probe cleanup terminated only owned process trees/jobs.

## Custody and delivery
- Target: local canonical main. Do not push recovered private history to the public remote; the established privacy-reviewed, history-free export owns public transfer.
- Prebuilt protocol: `docs/PREBUILT-UPDATES.md`. Signing, installation, controller changes and public publication were not executed.
- Historical persistence, GPUI companion and privacy receipts remain in `f0d4aec:WORKLOG.md`; current identity and executed checks above describe this recovery.

## GPUI rebuild parity list — FleetConsole 1.3.0 (added 2026-11-24)

Source build: FleetConsole 1.3.0, bundle version 11, arm64, `CFBundleShortVersionString 1.3.0` in `Scripts/assemble-app.sh`. Stack: Swift 6 (swift-tools 6.0), SwiftUI + AppKit, macOS 14+, targets `FleetCore`, `fleetd`, `fleetctl`, `FleetConsoleApp` in `Package.swift`; terminal via SwiftTerm 1.15.0; bundled Rust `fleet-agent` built from `rust/`; SQLite registry via system `sqlite3`. An experimental Rust GPUI companion already exists in `rust/fleet-gpui` (GPUI 0.2.2) and is explicitly not a replacement in `docs/RUST-PORT.md` and `README.md`. The GPUI rebuild must match every item below losslessly: same capability, same data, same limits. A smaller build that does less is a defect. Where 1.3.0 is macOS-only, the rebuild must provide the same function on macOS and on Linux (menubar on macOS, tray/status item on Linux), per Christian's GPUI spec for FleetConsole.

### Identity, bundle, and launch

- [ ] Bundle id `com.fleetconsole.app`, name/display name `FleetConsole`, executable `FleetConsole`, package type `APPL`.
- [ ] `LSUIElement true`: no Dock icon and no app-switcher entry; app runs with `.accessory` activation policy (`.regular` only for review builds).
- [ ] Minimum system macOS 14.0 (`LSMinimumSystemVersion 14.0`); Info.plist records `FleetSourceRevision`, `FleetSourceDirty`, `OurosDesignCoreVersion`, and `OurosDesignCoreSHA256`.
- [ ] Copyright string in plist: `Local-first. No telemetry, no network listeners.`
- [ ] App icon `AppIcon.icns` is shown in Finder, Get Info, notification banners, Login Items, and About despite `LSUIElement`.
- [ ] Single instance: a second launch hands off to the running instance, activates it, posts `com.fleetconsole.openDashboard` if `--dashboard` or `FLEETCONSOLE_DASHBOARD=1` was passed, then terminates itself.
- [ ] Launch flags: `--dashboard` and env `FLEETCONSOLE_DASHBOARD=1` open the Dashboard on launch; `--review` / `FleetConsoleReviewBuild` skips notification authorization, helper registration, and the Welcome window.
- [ ] On launch the app installs the main menu, creates the menubar item with autosave name `com.fleetconsole.item.fleet`, starts the controller subscription, and registers the helper if possible.
- [ ] On quit the app stops the DaemonClient subscription and signals all remaining app-owned agent process groups with SIGTERM, then SIGKILL after 2 seconds.

### Controller daemon `fleetd`

- [ ] `fleetd` is a separate executable bundled at `Contents/Resources/bin/fleetd`, registered as launchd agent `com.fleetconsole.fleetd` from `Contents/Library/LaunchAgents/com.fleetconsole.fleetd.plist` via `SMAppService.agent` on macOS 13+.
- [ ] Daemon plist: `RunAtLoad true`, `KeepAlive true`, `ThrottleInterval 10`, `ProcessType Background`, stdout/stderr to `/dev/null`, PATH `/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin`.
- [ ] If SMAppService registration returns `.requiresApproval`, the app only logs that approval is needed in System Settings → General → Login Items; fallback is `Scripts/install-agent.sh`.
- [ ] The menubar app never restarts the controller, so leases keep expiring and leaked processes keep being reaped while the UI is closed or crashed.
- [x] App and daemon communicate over an owner-only Unix socket at `~/Library/Application Support/FleetConsole/fleetd.sock`; the app subscribes with an RPC `subscribe` request and reconnects with backoff starting at 0.5s, doubling to a 5s cap.
- [ ] Daemon state persists in SQLite at `~/Library/Application Support/FleetConsole/registry.sqlite3`; the event history is append-only and is never pruned.
- [ ] Daemon tick, reconcile, and device-probe defaults come from `FleetConfig`: supervisor tick 5s, reconcile 20s, device probe 60s.

### Menubar item

- [x] Menubar item shows three template-image meter columns labelled `CPU`, `RAM`, and `DISK`, each with a percent value, or `—` when no sample exists; image height 20pt, label 7pt semibold, value 10.5pt monospaced-digit semibold.
- [x] Menubar alert text sits after the meters in 11pt monospaced-digit semibold: empty when healthy and connected, `Offline` when the controller is disconnected, `!N` where N is awaiting-reply count if any, otherwise `!N` where N is critical plus warning attention count.
- [x] Alert colour is system red when tint is `.bad` (disconnected or any critical), otherwise system orange; tint is `.warn` for awaiting replies or warnings, nil when healthy.
- [x] Menubar tooltip when disconnected is exactly `FleetConsole — controller not running`; when connected its first line is counts joined by ` · ` for running services, unmanaged count if any, critical count if any, and warning count if any.
- [x] Tooltip then lists up to the first 4 agent profiles as `id: headline`, appending ` — N awaiting your answer` when that profile has awaiting replies.
- [ ] Tooltip then shows `next lease expires <relative time>` when any agent profile has a lease expiry, then a network-fault line if one exists, then `fleetd up <duration>`.
- [ ] Network-fault tooltip lines cover, in order: no internet, no Ethernet and no Wi-Fi link, Tailscale installed but not running, and N unreachable devices with their names.
- [x] Accessibility label for the menubar button is `FleetConsole fleet — <tooltip with newlines replaced by commas>. <label value readings>` plus the alert text when present.
- [ ] Left click toggles the popover; right click or Control-click shows the context menu instead; opening the popover calls refresh-all and marks messages seen.
- [ ] Popover is an `NSPopover` with `.transient` behaviour, animation on, and preferred-content-size hosting.

### Right-click / context menu

- [ ] Context menu item: Quick View (symbol `gauge.with.dots.needle.67percent`).
- [ ] Context menu item: Needs Attention (symbol `exclamationmark.circle`, shortcut ⇧⌘H via the shared item).
- [ ] Context menu item: Agents, titled `Agents — N awaiting your answer` when N is above zero, shown only when the Agents section is enabled in config; symbol `person.2`.
- [ ] Context menu item: Open Dashboard, shortcut ⌘0.
- [ ] Context menu section header `Monitor This Mac` with module items for Overview, Processes, and Storage only, each with its module symbol.
- [ ] Context menu item: Network (the Connections section, titled Network).
- [ ] Context menu section header `Background Work` with module items for Services, Events, and Launch Services.
- [ ] Context menu item: New Task… with shortcut ⌘N, opening the Task Composer window.
- [ ] Context menu item: Find Background Processes, which triggers a reconcile sweep.
- [ ] Context menu items: Edit Configuration, Reveal Logs in Finder, and Replay Welcome.
- [ ] Context menu section header `Help` with FleetConsole Guide and fleetctl Setup… items.
- [ ] Context menu item: Quit FleetConsole with shortcut ⌘Q.

### Popover and Quick View

- [ ] Popover width is 480pt; header row shows the Fleet badge, title `FleetConsole`, and the fleet status line, which is `Controller offline`, `N awaiting your answer`, `N critical · M warning`, `N warning`, or `N services running`.
- [ ] Popover header buttons: dashboard button (symbol `square.grid.2x2`, help text includes ⌘0), an Agent menu button, and a Configuration menu button (symbol `ellipsis.circle`).
- [ ] Agent menu in the popover lists CPU, Memory, Disk, and Network, and each entry starts a metric investigation for that meter.
- [ ] Configuration menu in the popover lists Refresh, Edit Configuration…, Ouros Account…, and Source & Support; Refresh re-runs all probes, Source & Support opens the GitHub repo URL.
- [ ] Ouros Account… in the popover opens the Device Management sheet.
- [x] Quick View shows four instruments side by side in one horizontal strip: CPU dial, Memory dial, Disk, and Network.
- [x] CPU and Memory are retro gauges with a percent readout; CPU help text shows CPU brand and core summary, Memory help text shows used bytes and memory-pressure label.
- [x] Disk is a 20-cell grid (5 columns) with filled cells rounded from the used share, a percent readout, and help text showing available bytes of total bytes as capacity, not temperature.
- [x] Network shows separate Download and Upload readouts in bytes per second with bars on a fixed logarithmic scale from 0 to 1 GB/s, labelled as live physical-interface traffic, not link utilization.
- [ ] Each Quick View instrument has a context-menu Investigate action for its metric.
- [ ] Below the strip the popover provides the three action destinations named in the README: Agent, Diagnostics, and Preferences.
- [ ] Popover sections for Services, Agents, Processes, and Connections exist as `FleetSection` cases and are gated by config section switches; a requested non-Quick-View section opens the Dashboard on the matching module instead.
- [ ] Dismissed agent messages stay dismissed via the local message-dismissals store and do not reappear from the same mailbox snapshot.

### Main menus and Dashboard window

- [ ] Application menu: About FleetConsole, Hide FleetConsole (⌘H), Hide Others (⌥⌘H), Quit FleetConsole (⌘Q).
- [ ] Edit menu: Undo (⌘Z), Redo (⇧⌘Z), Cut (⌘X), Copy (⌘C), Paste (⌘V), Select All (⌘A).
- [ ] View menu: Open Dashboard (⌘0), Needs Attention (⇧⌘H), all six console modules, Terminal (⇧⌘T), Files (⇧⌘F), Focus Search (⌘K), Refresh (⌘R), Toggle Sidebar (⌃⌘S), Toggle Inspector (⌥⌘I), Enter Full Screen (⌃⌘F).
- [ ] Window menu: Minimize (⌘M), Zoom, Close (⌘W); Help menu: FleetConsole Guide and fleetctl Setup….
- [ ] FleetConsole Guide opens `https://github.com/janestreetshiller/fleet-console#readme`; fleetctl Setup… shows an alert explaining the bundled CLI, offers Copy Doctor Command, CLI Reference, and Close, and copies `'<bundled fleetctl path>' doctor` to the pasteboard.
- [x] Dashboard modules in order with shortcuts ⌘1 to ⌘6: Overview titled Agent awareness, Processes, Storage, Services titled Operations, Events, Launch Services titled Plists in code.
- [ ] Dashboard opens to the agent-first spatial awareness map, not to a table.
- [ ] Awareness map shows detected sessions by their actual published activity in project clusters, with evidence-backed connections only to matching process identities, observed process children, registered owners, managed services, and listeners.
- [ ] Awareness map never infers ownership or code dependencies from tool names, PIDs, or shared folders; stale registry evidence stays labelled as retained and cannot verify a process.
- [ ] Awareness map supports drag to pan, pinch or zoom buttons to zoom, fit-to-view, node selection with relationships and provenance, and search that finds activity plus its immediate context.
- [ ] Process and service inspectors remain available without leaving the map; diagnostic process tables, storage, and other detailed views stay under Tools and the View menu.
- [ ] Device sidebar starts tucked away; its toggle stays at the left edge of the window and the inspector toggle stays at the right edge.
- [ ] Dashboard is an opaque Liquid Glass scene in 1.3.0; the Overview controls sit in one toolbar row and process toolbar stacking is fixed.
- [ ] Agents & Map workspace (sidebar, or Operations → Agents) has fixed columns linking recorded owners to active services, identity-verified group leaders, and observed listeners, with search over owners, service names, IDs, and detected sessions, plus an exact-owner filter.
- [ ] Selecting a service in Agents & Map shows its purpose, lease, health evidence, logs, and existing actions; the roster and operator inbox remain in the same workspace.
- [ ] Detected sessions stay in a separate lane in Agents & Map; declared ports stay labelled as declarations, missing or stale samples show as unavailable, and a disconnected controller retains clearly labelled observations.

### Directory Crystal

- [ ] Directory roots render as a crystalline folder-containment structure behind activity: roots are foundations, child folders branch on a triangular lattice and show immediate child-folder counts.
- [ ] Selecting a vertex or its child navigator allows inspect, focus, open, expand, and collapse of that branch.
- [ ] Roots → Choose roots… selects local folders and remembers them; an existing `~/Code` is the default workspace root, persisted in UserDefaults.
- [ ] Roots → Fit roots shows the complete observed structure; Roots → Focus activity restores readable agent context; actual project paths anchor to observed directory vertices.
- [ ] Directory reads are metadata-only, asynchronous, and cancellable, refreshed from the existing observation pulse at most every 30 seconds or on explicit refresh or expansion.
- [ ] Initial directory view is 3 levels deep and bounded to 600 folders and 12,000 directory entries; coverage limits and unreadable counts are shown explicitly and expansion prioritises the chosen branch.
- [ ] Hidden and generated folders and symbolic links are excluded from the directory structure; automatically discovered roots never request private-folder or volume access.

### What is monitored, and from where

- [ ] Local system sampling every 2 seconds: CPU, GPU, memory including pressure, storage capacity plus read/write bytes and ops per second, network traffic per physical interface, power/battery, SMC sensors when the premium feature is unlocked, and thermal state.
- [ ] Process inventory sampling every 4 seconds by default from config `processSampleSec`, clamped to a 2-second minimum.
- [ ] Network monitor refresh every 20 seconds by default from config `networkRefreshSec`, clamped to a 5-second minimum, covering internet reachability, Ethernet, Wi-Fi including SSID, Tailscale state, connections, routing, and VLAN/network segments from config.
- [ ] A 1-second clock timer drives relative-time updates and expires topology evidence after its validity deadline; topology evidence expires after 3 controller ticks (15 seconds at the default 5-second tick).
- [ ] Controller snapshots supply services, devices, agent summaries, agent profiles, mailbox messages, external services, detected sessions, unmanaged processes, attention items, and recent events.
- [ ] Storage module scans and breaks down disk use; Processes module shows the process table with heatmap and inspector; Events module shows the append-only event history.
- [ ] Host probes check configured devices for reachability; device probe interval defaults to 60 seconds.
- [ ] Agent-cost probing exists and runs only when `showAgentSpend` is enabled in config; local agent-spend estimates are off by default.
- [ ] Network probes inspect connections and routing only and never change network settings.

### Services, leases, and process control

- [ ] A service launched through the controller records name, owner, purpose, working directory, argv, declared ports, lease, and stdout/stderr logs.
- [ ] Default lease is 1 hour, maximum lease is 12 hours, stop grace is 10 seconds, unmanaged grace is 15 minutes, and crash attention window is 15 minutes, all from `FleetConfig` defaults.
- [ ] The app and CLI can pause, resume, renew, restart, and stop controller-launched services; pause uses SIGSTOP, resume uses SIGCONT, and a paused service keeps its ports and memory and is skipped by health checks and lease decisions.
- [ ] Stop re-verifies pid, recorded start time, and process group, then sends SIGTERM to the group and SIGKILL after the grace period; kill requests immediate SIGKILL with the same identity checks.
- [ ] Services with unrenewed leases have their process groups cleaned up even after the launching agent disappears; paused services are exempt until unpaused.
- [ ] Health checks support HTTP (localhost only) and TCP with 15-second interval, 4-second timeout, expected status 200, and failure threshold 3 by default at launch time.
- [ ] A listener outside a service's allowed-port set is flagged; ignored ports default to 22, 88, 445, 631, 3283, 5900, 7000 and the ephemeral floor defaults to 49152.
- [ ] Processes started elsewhere stay unmanaged; reconcile finds listeners and dev-server-shaped processes outside the registry using the configured dev-server patterns.
- [ ] `claim` records owner, purpose, and lease for an existing process but grants no signalling authority: stop, restart, pause, resume, kill, and the lease reaper all refuse claimed records, and an expired claim is reported and left alone.
- [ ] Optional End Process is a separate owner-only SIGTERM control and is disabled by default via `allowProcessTermination false`.
- [ ] Before any signal the controller verifies process identity; unmanaged processes are reported and never signalled by the controller or by Fleet Agent.

### Agents, mailbox, investigations, and fixers

- [ ] Operator mailbox: agents post messages with `fleetctl notify`; `--ask` marks a message as needing a reply, `--problem` marks a failure, and plain status messages never interrupt.
- [ ] The app can reply to a mailbox message exactly once and can mark messages seen when the popover opens.
- [ ] Needs Attention collects health-check failures, repeated recorded crashes, lease expiry, missing declared listeners, port violations, and unmanaged work as distinct findings with distinct remedies.
- [ ] Choosing an installed fixer hands it a Needs Attention finding; Claude Code, Codex, and Fleet Agent open in separate terminal sessions and never type into the user's shell.
- [ ] The Session picker switches between the warm shell, up to 4 agent sessions, and the latest account-backed read-only investigation; starting another agent never replaces a running one and requests are never evicted automatically.
- [ ] Session Details shows the request, working directory, permission and billing policy, and troubleshooting options, and the same options are included in the saved request the agent receives.
- [ ] Troubleshooting suggestions are capped at 8 and ranked by matching events in the latest 200 supplied events within 6 hours; counts are labelled as local observations, zero means no matching attributable event was supplied, and legacy unmanaged events are not merged into fabricated counts.
- [ ] Stop… for an agent session confirms first, then SIGTERM to the app-owned group and SIGKILL after 2 seconds while child identity is verified; the session stays in Stopping state until cleanup finishes and closing the PTY alone is not treated as proof of exit.
- [ ] Stop waiting cancels an account investigation without clearing an unconfirmed paid-operation identity and without automatic retry; window close also cancels waiting.
- [ ] Fleet Agent stays proposal-only and account-backed investigations stay output-only; generic commands are accepted only in the Shell session and are never injected into an agent or investigation.
- [ ] Saved fixer request files stay local and owner-only under `~/Library/Application Support/FleetConsole/fix-reports`.
- [ ] Bundled Rust Fleet Agent exposes 15 typed tools over the `fleetd` socket (snapshot, ps, memory ranking, specialist memory advice, logs, events, launch, stop, restart, pause, resume, kill, renew, reconcile, operator mailbox), never raw shell; mutating tools require `confirm:true` and a reason written to the append-only event log.
- [ ] Fleet Agent also serves the same tool surface as an MCP stdio server over JSON-RPC 2.0 with a byte-stable hash-pinned `tools/list` and fail-closed `tools/call`, and its `propose`/`ask` loop is read-only, serialised, and bound to an explicitly configured already-running loopback endpoint only.
- [ ] Fleet Agent memory knowledge classifies each service's memory trend as Climbing, Creeping, Oscillating, or Steady, triages process memory, derives macOS pressure verdicts from compressor and swap counters, and ranks unanswered operator mail above every technical finding.
- [ ] Fleet Agent metering appends one HMAC-signed `FLTA-` record per turn to `~/Library/Application Support/FleetConsole/agent-billing/meter-ledger.txt`; invalid signatures are counted and excluded, never summed.

### Terminal and Files tools

- [ ] Terminal tool (⇧⌘T) requires tmux; if tmux is missing the user is told to install it and reopen Terminal.
- [ ] The shell session attaches to the `shell` session on the separate `fleet-console` tmux server (SwiftTerm PTY surface), so the shell and its running jobs survive window close and panel changes.
- [ ] Closing the window or quitting the app detaches the tmux client only; the session ends only when its shell exits, the server is stopped, the user logs out, or the machine restarts, and reopening reattaches to the existing session.
- [ ] The shell working directory is chosen when the session is first created; later navigation does not change a running shell's directory; ending it deliberately is done by exiting the shell or running `tmux -L fleet-console kill-server`.
- [ ] Commands in the shell become supervised only when launched through `fleetctl`; panel toggles keep processes warm, while window close ends app-owned agent children including hidden or deferred sessions.
- [ ] Agent session metadata and scrollback are not restored after quitting; the tmux shell session is the only session that persists.
- [ ] Files tool (⇧⌘F) requires Yazi and uses the bundled Yazi config under `Contents/Resources/yazi` with dark and light themes.

### Devices and multi-device access

- [ ] Link a Device… flow: connect the Ouros account, subscribe to multi-device access, then enter device name and hostname or IP, with optional SSH username and opt-in to reading that device's FleetConsole service inventory; first-run setup creates no example peers.
- [ ] The controller probes linked-device reachability and reads metrics through the user's existing SSH configuration; remote processes are read-only and unlinking removes only the configuration entry.
- [ ] This Mac must remain awake for linked-device monitoring; deployable agents and the FleetConsole MCP are planned only and are not part of 1.3.0 behaviour.
- [ ] Multi-device access costs $10 USD per month through Ouros, is a separate entitlement from Ouros Pro, and does not include AI credits; cancellation and payment status come from Ouros billing.
- [ ] The device screen links to Ouros billing for prepaid AI credits; the Agents section opens Ouros Agent for a metered credit-funded review where each model round is metered, a stopped or uncertain request is not retried automatically, and a proposed restart needs separate operator approval and is performed only for a controller-launched service.

### Settings, configuration, and persistence

- [ ] All configuration lives in `~/Library/Application Support/FleetConsole/config.json`, written atomically with permissions 0600; support, log, and service-log directories are created with permissions 0700.
- [ ] Edit Configuration opens `config.json` in an editor; the app watches the config directory and reloads the config live on write, rename, or delete, falling back to defaults with a load error shown only when an unreadable file exists.
- [ ] Config controls visible sections (services, agents, processes, network, devices, listening; all default true), polling intervals, known computers/devices, network segments, expected listeners and known services, ignored listener commands and ports, and the process-termination feature flag.
- [ ] If no config exists, the app creates a default config whose only device is the self device (`This Mac` or the host name, localhost, plus its Tailscale name when known).
- [ ] Preferences in the Dashboard includes Matte/Glass shell material, agent defaults, and account access; Reduce Transparency forces an opaque backing.
- [ ] UserDefaults keys: `fleetconsole.welcomeShown` and `fleetconsole.skipWelcome` for the Welcome flow, the Directory Crystal roots preference, `fleetconsole.laterTasks.v1` for deferred tasks, message dismissals, service labels, and Ouros billing operation keys.
- [ ] Service labels (custom name and colour per service) persist locally and can be cleared by removing both name and colour.
- [ ] Credentials for Ouros account work are isolated from the app's ordinary state, use the Keychain when not in a verification build, and development credentials never mix with production credentials.
- [ ] Registry and configuration stay in `~/Library/Application Support/FleetConsole`; daemon and service logs stay in `~/Library/Logs/FleetConsole` with per-service stdout and stderr files under its `services` subfolder; Reveal Logs in Finder opens that log folder.
- [ ] The state root can be overridden with the `FLEETCONSOLE_STATE_ROOT` environment variable, which relocates the home base for support and log paths.

### Notifications, sounds, and Welcome

- [ ] The app requests notification authorization for alerts and sounds once, on first non-review launch.
- [ ] A system notification with the default sound is posted only for a fresh mailbox message that is awaiting a reply or marked as a problem, never for plain status messages and never for messages present in the initial load.
- [ ] Notification title is `<agent> needs an answer` or `<agent>: problem`, body is the message body, subtitle is the service name when present, and the request identifier is `fleet.message.<message id>`.
- [ ] No other sounds are played by the app in 1.3.0.
- [ ] Welcome window (560 by 420) appears once on first launch unless `fleetconsole.skipWelcome` is set, can be replayed from the context menu, and offers Skip and a do-not-show choice; it states the three headline capabilities: explore CPU and memory over time, inspect processes/services/leases, and link more computers through the device add-on.

### Ouros account, billing, and freemium seam

- [ ] Local monitoring and service control are free with no licence required for MIT builds; the offline `FLT1-` licence seam and `fleetctl license` minting remain as legacy compatibility only.
- [ ] Ouros account sign-in uses an account-backed device flow with a verification URI, a 5 to 60 second polling interval that backs off by 5 seconds on `slow_down` up to 60 seconds, and no automatic retry of a stopped or uncertain paid operation.
- [ ] Ouros Agent displays the charge returned by the gateway for each review; the local app never invents a price for a gateway round.
- [ ] Premium gating in the local sampler is limited to the SMC-sensors feature check; all other local telemetry is ungated.

### `fleetctl` CLI

- [ ] `fleetctl` is bundled at `FleetConsole.app/Contents/Resources/bin/fleetctl`, has no external package dependencies, and exits 0 on success, 1 on rejection or not-found, and 69 when the controller is unavailable.
- [ ] Ask commands: `launch`, `renew`, `stop`, `restart`, `pause`, `resume`, `kill`, with the launch options, defaults, and limits documented in `docs/CLI.md` (required name, owner, and purpose; lease default 1h; health interval 15s and timeout 4s).
- [ ] Look commands: `list [--all] [--json]`, `show [--json]`, `agents [--json]`, `events [--limit 50] [--json] [--offline]`, `logs [--err] [--bytes 64000]`, `ping`, `doctor`, and `topology [--owner <exact-id>] [--json] [--snapshot <path>]`.
- [ ] Talk commands: `notify [--ask] [--problem] [--service <id>]`, `inbox [--agent <a>] [--unanswered] [--json]`, and `reply <message-id>`, which refuses a second reply to the same message.
- [ ] Housekeeping commands: `reconcile`, `claim`, `ignore <command>` (which appends to `ignoredListenerCommands` in config and writes an event), `prune [--older-than 1h]` (which drops only stopped and crashed service records), and `config [--path | --reload]`.
- [ ] `doctor` checks socket presence and 0600 permissions, the launchd agent, controller answers, supervisor ticking, reconciler sweeping, registry, config, log directory, the tailscale CLI, and current counts, and waits out launchd's restart throttle before declaring a controller fault.
- [ ] `events --offline` opens the existing registry read-only so history remains available with the controller down; it provides no live state.
- [ ] Durations in the CLI accept `30s`, `15m`, `2h`, `1d`, or a plain number of seconds; environment values passed at launch are never persisted.
- [ ] Topology output is versioned JSON with `generatedAt`, `isStale`, `validUntil`, typed nodes, edges with provenance and observation times, and limitations; CPU and memory are nullable and missing, invalid, or expired samples stay unavailable.

### Update path and release

- [ ] There is no in-app auto-updater and no Sparkle feed in 1.3.0; updates arrive as new signed builds, never as silent self-replacement.
- [ ] Release builds are produced by `Scripts/build-app.sh release` into a fresh staging directory; the script refuses an existing `FleetConsole.app` in the output, signs nested code before the app, and validates with `codesign --verify --deep --strict`.
- [ ] Ad-hoc builds use identity `-`, no timestamp, and are local review artifacts only; Developer ID builds use hardened runtime and a secure timestamp and are then notarized with `Scripts/notarize.sh`, stapled, and validated with `stapler validate` and `spctl --assess`.
- [ ] GitHub Releases are published by `.github/workflows/release.yml` on `v*` tags from macos-15: DMG plus its sha256 and `FleetConsole-macos-arm64.zip` plus its sha256, built only when signing secrets exist.
- [ ] Installing over `/Applications/FleetConsole.app` is a separate authorised step done by `Scripts/update-installed.sh <git-ref>`, which builds from a clean detached worktree, verifies revision and signature, quits the client, moves the old bundle to Trash, copies the new app, verifies it, and launches it; it does not restart `fleetd` unless `--restart-controller` is passed.
- [ ] Prebuilt transfer mode (`Scripts/update-installed.sh <ref> --prebuilt` with `Scripts/prepare-prebuilt.py` and `Scripts/verify-core-update.py`) verifies Developer ID, the stapled ticket, Gatekeeper, clean source metadata, predecessor identity, and core SHA-256 before replacement, and retains the previous app for rollback while `fleetd` keeps running.
- [ ] The bundle ships both licence files at `Contents/Resources/licenses/FleetConsole-LICENSE.txt` and `SwiftTerm-LICENSE.txt`, the AppIcon, the Yazi resources, and the `fleetd`, `fleetctl`, and `fleet-agent` binaries under `Contents/Resources/bin`.
- [ ] Wi-Fi SSID display requires the Location When In Use permission; the plist usage string states that nothing is collected, stored, or transmitted, and signal strength, link rate, and IP work without it.

### Appearance, accessibility, and platform behaviour

- [ ] The interface uses macOS fonts, system appearance colours, and native controls, and renders in both light and dark appearance.
- [ ] Shared surfaces honour Reduce Motion and Increase Contrast, and Reduce Transparency forces an opaque backing.
- [ ] Device fields retain their labels and selectable process rows work with the keyboard.
- [ ] All keyboard shortcuts ⌘0 to ⌘6, ⇧⌘H, ⌘K, ⌘R, ⌥⌘I, ⇧⌘T, and ⇧⌘F work exactly as listed in the README shortcut table.
- [ ] Design identity is pinned by the design-core receipt: brand signal `#F17B33` with the action and ink colours recorded in `.design-core/receipt.json`, verified at build time by the `VerifyDesignCore` SwiftPM plugin.

### GPUI rebuild scaffold (2026-11-24)

Production GPUI app scaffolded in a new crate, `rust/fleet-console` (binary `FleetConsole`, workspace member). The experimental companion in `rust/fleet-gpui` was not used as the base: it opens a main window at launch, its macOS status item shows no meters, and it has no Linux tray, so a fresh menubar-first crate is cleaner than untangling its 5,780 lines. The companion and the Swift app stay untouched.

What exists now: identity (`com.fleetconsole.app`, executable `FleetConsole`, version 1.3.0; macOS bundle assembled by `rust/fleet-console/scripts/build-macos-app.sh` from `rust/fleet-console/macos/Info.plist` with `LSUIElement true`, `LSMinimumSystemVersion 14.0`, package type `APPL`); launch with no main window, resident in the menubar/tray; the menubar shell in skeleton form — three meter columns CPU / RAM / DISK with `—` placeholder readings, a click that toggles a small popover (360x210) saying the controller is not connected yet, and a Quit item (popover button, tray menu on Linux, right-click menu on macOS, Cmd-Q / Ctrl-Q). Bridges: macOS uses a small Objective-C `NSStatusItem` bridge in `src/main.rs` (autosave name `com.fleetconsole.item.fleet`, tooltip `FleetConsole — controller not running`, Accessory activation policy set in code because GPUI hardcodes Regular); Linux uses a ksni StatusNotifierItem (GPUI 0.2 has no tray; ksni is pure Rust over D-Bus, blocking API on its own thread) with a `#F17B33` pixmap icon and the meter text in its menu and tooltip.

Parity items covered in skeleton form: bundle id / name / executable / package type; `LSUIElement` with `.accessory` policy; minimum macOS 14.0; copyright string in the plist; menubar item installed at launch with the parity autosave name; menubar three meter columns with `—` readings; disconnected tooltip text; left click toggles the popover; Quit FleetConsole item. Everything else on the list is untouched and still open: no controller connection, no real samples, no Dashboard, no menus beyond Quit.

Verified 2026-11-24: macOS release build and bundle on OurDev (Mac mini M4) — app launched in the Aqua session, `lsappinfo` reports type UIElement, status-item anchor measured in the menubar (x=1553, width=171 on the 1920x1080 display), `--popover` opened the 360x210 popover window (CGWindowList), quit exited cleanly; screenshot and synthetic-click checks from SSH were blocked by macOS TCC (no assistive access, no display capture), so the status-item click itself was not driven on macOS. Linux debug build on OurStation (arm64, Hyprland/quickshell) — StatusNotifierItem registered on the session bus with the orange pixmap served over D-Bus, a D-Bus `Activate` call opened the popover showing the three `—` meters, `Controller not connected yet`, and the Quit button (grim screenshot), and the tray menu Quit item (dbusmenu Event) exited the process cleanly.


### GPUI rebuild — local sampling bite (2026-11-24)

The menubar meters are real now. `rust/fleet-console/src/sampler.rs` samples this machine every 2 seconds on a dedicated thread (parity item 75 cadence) and pushes each reading through the shell event channel to the macOS status item title and accessibility label, the Linux tray menu and tooltip text, and the popover meter row, which all show the same values. Until the first sample lands a meter shows `—`, and a reading a platform cannot produce falls back to `—` for that meter alone. Definitions copy the Swift build (see the crate README for the full list): CPU busy share from processor-tick deltas (1 minus idle share, first read primes only), macOS RAM as (app + wired + compressed) / total from `host_statistics64`, disk as (total - available) / total for `/`.

Parity items made real by this bite: item 17 (menubar three meter columns with live percent values) fully; item 75 for the CPU, memory, and disk readings only. Still placeholder or untouched: everything else in item 75 (GPU, memory pressure, storage read/write rates, network, power/battery, SMC sensors, thermal state), the controller connection and all controller-fed data, menubar alert text and colours (items 18-19), tooltip agent lines (items 20-23), popover instruments and gauges (items 44-48), and notifications. The controller-offline presentation is unchanged.


### GPUI rebuild — controller connection bite (2026-11-24)

The GPUI app talks to the controller now. A dedicated thread (`rust/fleet-console/src/controller.rs`) subscribes to fleetd over the owner-only Unix socket and streams snapshots into the shell, with the Swift reconnect policy: backoff starts at 0.5s, doubles per failure, caps at 5s, and resets on a successful subscribe. Snapshots are typed in `rust/fleet-console/src/snapshot.rs` against the live daemon's JSON, and every menubar derivation copies the Swift rules (AppModel.fleetAlert / fleetStatusLine / fleetTint / fleetTooltip, AgentProfile.headline, Fmt.duration / relative / ports): the macOS status item title appends the alert text (`Offline` when disconnected, `!N` for awaiting replies or attention) with the alert suffix tinted system red or system orange via an attributed title, the tooltip carries the counts line, up to four agent profile lines, the next-lease line, and the fleetd uptime line, and the accessibility label follows the Swift formula. The popover header now shows the fleet status line instead of the placeholder text. Opening the popover sends the markSeen and refreshDevices one-shots, as the Swift build does. The Linux tray shows the same alert and tooltip text.

Parity items checked off by this bite: item 13 (app subscribes over the owner-only socket and reconnects with 0.5s-to-5s backoff), item 18 (menubar alert text), item 19 (alert colour), item 20 (disconnected tooltip text and the connected counts line), item 21 (tooltip agent profile lines), and item 24 (accessibility label), all in this bite's commit; item 17 (menubar meter columns) is also checked off here, on the strength of the local sampling bite (1050f85). Item 22 is covered except its network-fault line, which waits on the network monitor (item 77). Items 10-12 and 14-16 describe the bundled fleetd itself, which ships unchanged. Still open: the network-fault tooltip lines (item 23), the Quick View instruments (items 44-48), the full context menu (items 27-39), and everything after.

Verified 2026-11-24: `cargo test -p fleet-console` passes the snapshot derivation tests (healthy, awaiting-reply, and critical fixtures, plus the Fmt formats) on macOS and Linux. Linux debug build on OurStation: the StatusNotifierItem published, real meter values flowed, and the controller thread cycled with backoff against the absent Linux socket, reporting the disconnected state. The macOS release bundle was built on OurDev by `scripts/build-macos-app.sh`; its Aqua-session run against the live fleetd is still owed, because OurDev stopped accepting SSH sessions partway through this bite (its process table filled; the machine answers pings but sshd cannot fork). The derivation code is platform-shared, and the macOS status-item wiring compiles into the same binary that was assembled there.


### GPUI rebuild — Quick View bite (2026-11-24)

The popover is 480pt wide and carries the Quick View strip. The sampler (`src/sampler.rs`) now produces a full reading every 2 seconds: CPU and memory shares, memory used and total bytes, memory pressure (from `kern.memorystatus_vm_pressure_level` on macOS, with the Swift labels normal / elevated / critical), disk used share with available and total bytes, physical-interface network rates (loopback and virtual interfaces excluded, rates from per-refresh byte deltas), and the CPU brand plus core summary (Apple-silicon performance/efficiency split included). The strip (`src/quickview.rs`) draws the four instruments at the Swift sizes: CPU and Memory retro gauges with the RetroGauge geometry (240° sweep from 150°, 40 ticks, redline from 0.90, tapered needle, percent readout inside the dial) and the SystemThresholds tones, the Disk 20-cell grid with cells filled by the rounded used share and coloured per cell by the free-space thresholds, and the Network Download/Upload readouts with bars on the fixed log scale from 0 to 1 GB/s. Help texts are wired as tooltips with the Swift strings: CPU brand plus core summary, memory used bytes plus pressure label, disk available of total as capacity, and the network live-traffic label.

Parity items checked off by this bite: item 44 (the four-instrument strip), item 45 (retro gauges, readouts, and help texts), item 46 (disk grid, readout, and help text), and item 47 (network readouts and log-scale bars), all in this bite's commit. Item 40 is covered except the Fleet badge in the header. Still open in this section: the header buttons and the Agent and Configuration menus (items 41-43), the Investigate context actions (item 48), the three action destinations below the strip, the config-gated sections, and message dismissals.

Verified 2026-11-24: `cargo build` and `cargo test` pass on Linux. The debug build ran on OurStation with the popover open and was screenshot-checked: both gauges rendered with value arcs, needles, ticks, and redlines against live values (CPU 18%, Memory 56%), the disk grid showed the rounded filled cells at 31%, and the network bars moved with live traffic (57 KB/s down, 4.5 KB/s up in the checked frame). The macOS run is still owed with the controller bite's, while OurDev is unreachable.


### GPUI rebuild — Dashboard bite (2026-11-24)

The Dashboard window exists (`src/dashboard.rs`). It opens from the popover's new Dashboard button, from the View menu, and with ⌘0, and its six modules switch from the sidebar, the View menu, or ⌘1 to ⌘6, in the Swift order with the Swift titles: Overview (Agent awareness), Processes, Storage, Services (Operations), Events, Launch Services (Plists). Every module shows real data. Overview shows the fleet status line, the counts, the agent profile lines, and this machine's meters, all from the live snapshot and sampler. Services lists the snapshot's services with the Swift state labels, owner, effective ports, CPU, memory, restart count, and purpose (`FleetView.service_rows`). Events lists the snapshot's recent events newest first with the Swift kind labels and bad-kind colouring (`FleetView.event_rows`). Processes shows the top 25 local processes by CPU from a dedicated 4-second process sampler. Storage lists every mounted disk with a used bar and available-of-total bytes. Launch Services reads the platform inventory — `launchctl list` on macOS, `systemctl --user list-units` on Linux — when the Dashboard opens and on Refresh (⌘R, which also sends the controller a refreshDevices). The Help menu's FleetConsole Guide opens the repo README URL. A `--dashboard[=module]` launch flag exists as a verification aid, like `--popover`.

Parity item checked off by this bite: the Dashboard modules item (six modules in order, ⌘1 to ⌘6), in this bite's commit. Partially covered, not checked off: the View menu (Open Dashboard, the six modules, and Refresh are in; Needs Attention, Terminal, Files, Focus Search, sidebar and inspector toggles, and full screen are not), the Application, Edit, and Window menus (only Quit FleetConsole is wired), the popover header buttons (the dashboard button is in; the Agent and Configuration menu buttons are not), the process-sampling item (4-second cadence runs, the config interval does not drive it yet), and the module-depth item (Processes table and Events history are real; Storage shows capacity per disk, not a scanned breakdown; the Overview awareness map is not built — Overview shows the agent-first summary the map is drawn from, and the Directory Crystal is untouched).

Verified 2026-11-24: `cargo build` and `cargo test` pass on Linux. The debug build ran on OurStation with `--dashboard=processes` and `--dashboard=launch` and was screenshot-checked both times: the Processes table listed live processes sorted by CPU with real memory figures, and the Plists module listed the real systemd user services with active and inactive states. The macOS run is still owed while OurDev is unreachable.


### GPUI rebuild — macOS verification addendum (2026-11-24)

The macOS run owed by the controller and Quick View bites is now verified. OurDev accepted SSH again after its process table cleared; its checkout was reconciled (the uncommitted controller-bite files were identical to commit bd52bc6 and were replaced by a fast-forward pull; the pre-existing Package.swift and Package.resolved changes are not part of this rebuild and were left untouched). At commit 0b823eb: `cargo test -p fleet-console` passes on macOS, the release bundle builds with `scripts/build-macos-app.sh`, and the bundled app launched in the Aqua session showed the status item installed, `controller connected=true` against the live fleetd, the real fleet status `1 awaiting your answer` with alert `!1` derived from the live snapshot, and live meters (CPU 42-73%, RAM 34-36%, DISK 87% across the captured seconds). The instance was quit after the check; the installed Swift FleetConsole and its fleetd were not touched. Still unverified on macOS: a screenshot of the popover and Dashboard (SSH has no display-capture permission on this machine; both are screenshot-verified on Linux, and the macOS binary is the same code).
