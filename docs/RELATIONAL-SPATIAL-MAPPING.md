# Relational Spatial Mapping Architecture (GPUI / OS-Agnostic)

## 1. Paradigm Shift Overview
FleetConsole has transitioned from a macOS-exclusive, tabular-siloed utility into a cross-platform, high-performance spatial workspace built with GPUI in Rust.

Instead of fragmenting system state across isolated tables ("Processes", "Storage", "Services", "Needs Attention"), the console organizes operations into four unified relational planes centered on spatial mapping:

1. **Topography (Spatial & Relational Map):**
   - GPU-accelerated force-directed and hierarchical graph layout.
   - Interactive nodes: Agents (`Ouros`, `Codex`, `Claude`), Host cluster, Runtime core, OS worker processes, storage pools, memory pools.
   - Relational edges: IPC pipes, shared memory (`SHM`), socket connections (`SOCK`), parent-child process relationships (`PROC`), data flows.
   - Heat and volume scaling: Node area is scaled by RAM footprint / volume headroom; edge pulsations scale with CPU consumption and I/O throughput.

2. **Brain & Agents (Ouros-X Adapter Plane):**
   - Direct integration via the `ouros-adapter` bridge module.
   - Tracks active agent state transitions (`Idle`, `Reasoning`, `ToolExecution`, `AwaitingInput`, `Suspended`, `Terminated`).
   - Context-window memory utilization meters (tokens vs. heap and prompt cache bytes).
   - Token budget tracking, consumption velocity (tokens/sec), and cost calculations.
   - Decision trees with confidence scores, rationale trails, and invoked tools.

3. **Execution & Telemetry (Processes & Resources):**
   - OS-agnostic metric collection behind the `TelemetryProvider` trait (`SysinfoTelemetryProvider` / `SimulatedTelemetryProvider`).
   - Configurable `HardwareProfile` eliminating hardcoded `launchd` or Apple Silicon `E/P` assumptions.
   - Live CPU/GPU/RAM metrics directly associated with their agentic or system owners.

4. **Substrate (Storage & Volumes):**
   - Spatial memory maps, persistent cache trees, mount points, volume headroom, and I/O rates.

---

## 2. Sidebar: Descriptive Topology Map
The static button list has been replaced by a live, zoomable structural tree:
```text
Cluster / Host (Metal-01)
  └─ Runtime Core
      ├─ Active Agents (Ouros Core Brain, Codex Synthesis)
      ├─ Worker Processes (swift-frontend, WindowServer)
      └─ Substrate Storage (Mounts & Cache Pools)
```
- **Visual Status Indicators:** Nodes glow with cyan, amber, or crimson intensity based on thermal pressure, saturation (>90% CPU), and memory lock state.
- **Direct Spatial Focus:** Clicking any branch or cluster in the tree focuses and centers the viewport on that subsystem.

---

## 3. Integrated Diagnostics Drawer ("Needs Attention" Overhaul)
- The empty standalone tab is removed.
- Health checks are transformed into contextual badges attached directly to affected nodes on the spatial map.
- Badges offer one-click remediation actions:
  - `KillProcess(pid)`
  - `ThrottleAgent(agent_id)`
  - `CompactContext(agent_id)`
  - `PurgeCache(mount)`
  - `DrainSockets(target)`
  - `RestartDaemon(name)`

---

## 4. Persistent Contextual Terminal & Inspector
- The right rail hosts a split terminal dynamically bound to the selected entity:
  - Selecting an **Agent** attaches to its agent log stream and socket REPL (`ouros-cli attach --agent <id> --socket <addr>`).
  - Selecting a **Process** opens process shell context and inspection metadata (`lldb -p <pid> || top -pid <pid>`).
  - Selecting a **Volume** opens the terminal at that mount point.
  - Selecting the **Host** provides system console access.

---

## 5. Verification Commands
```bash
# Run identity receipt
cargo run -p fleet-gpui -- --identity

# Run automated headless verification of all 4 planes
cargo run -p fleet-gpui -- --verify

# Run test suite
cargo test --workspace
```
