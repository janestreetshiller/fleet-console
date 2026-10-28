# Fleet Console design package

Terminal overhaul, cluster gauge panel and website section for Fleet Console, in one phosphor-green system built from the F/C logo grid.

## Contents

| File | Purpose |
| --- | --- |
| `assets/fleet-console-logo-terminal.svg` | Logo: F (bright green) and C (dark green) on one grid, overlap cells dithered |
| `tokens.css` | Color, type, grid-cell and state tokens shared by every surface |
| `tui.html` | Interactive TUI mockup. Keys 1-6 or click the tabs |
| `gauges.html` | Cluster gauge panel, one tile per node |
| `website-section.html` | Product page section that embeds both previews |

## Design language

- Two greens only: `--fc-bright` (#55ff55) for the F tone, active state and healthy values, `--fc-dark` (#00aa00) for the C tone and fills. Amber and red appear only for warning and critical state, never decoration.
- The 10px grid cell from the logo is the base unit. Gauge segments, volume map blocks and the TUI's block characters all snap to it.
- Hard edges, no radius, no shadows. Depth comes from 1px `--fc-line` borders and dither.
- Monospace throughout. No uppercase letter-spaced eyebrows and no decorative glyph separators.
- Reduced motion: the only animation is the cursor blink, disabled under `prefers-reduced-motion`.

## TUI overhaul

Six views, one persistent header and key hint footer.

1. **Overview**: cluster summary, needs-attention list, active agents.
2. **Processes**: relational tree (service, child, sibling), CPU and memory per row.
3. **Services**: managed services table with state, pid, uptime, restarts. Actions: restart, stop, tail logs, renew lease.
4. **Agents**: transcript of a running agent with an inline approve/deny prompt.
5. **Storage**: volume map where area is allocated bytes, plus largest paths.
6. **Attention**: fix reports with the agent action available for each.

Keymap: `1-6` switch view, `j/k` move, `enter` inspect, `/` filter, `r` restart, `s` stop, `t` tail, `a` hand the selected item to an agent, `y/n` approve or deny, `?` help, `q` quit.

Rules: agents act only through `fleetctl` and never signal processes directly. Destructive actions (stop, clear cache) always show a confirmation line first. The selected row is a solid dark-green bar with black text.

## Cluster gauge panel

- One tile per node: name, health label, five 20-segment gauges (cpu, mem, gpu, net, disk), a 40-sample CPU history, and a footer with services up/total, agent count and uptime.
- Thresholds: dark green to 50%, bright green 50-70%, amber 70-90%, red above 90%. The tile border follows the worst gauge.
- Offline nodes dim to 50%, show `--` instead of values, and keep disk since it is last-known.
- Summary bar: nodes online, average cpu/mem/gpu, total agents, count needing attention.
- Color is never the only signal: the tile carries a text state (healthy, pressure, critical, offline).

## Data contract (proposed)

Per node, polled every 3s: `name, state, cpu, mem, gpu, net, disk (0-100), services {up,total}, agents, uptime, cpuHistory[40]`. Mockups use sample data; wire to the existing `fleetd` telemetry feed.

## Status

Design proposal only. Nothing here changes the shipping app. The native surfaces keep following `docs/DESIGN-SYSTEM.md`; this package explores a terminal-style direction for the `fleetctl` TUI, a cluster gauge panel, and the product website. Mockups use synthetic node names and data.

To preview, serve the folder (`python3 -m http.server` from `design/`) and open `tui.html`, `gauges.html` or `website-section.html`. Opening files directly loses the shared stylesheet.
