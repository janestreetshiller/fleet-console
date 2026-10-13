#!/usr/bin/env python3
"""Enforce the fleet-agent bundle boundary before signing."""
from pathlib import Path
import sys

MAX_AGENT_BYTES = 16 * 1024 * 1024
MODEL_SUFFIXES = {".gguf", ".safetensors"}
INFERENCE_BINARIES = {"llama-server", "llama-cli", "ollama", "mlx_lm.server"}


def verify(bundle):
    bundle = Path(bundle)
    agent = bundle / "Contents/Resources/bin/fleet-agent"
    if not agent.is_file() or agent.is_symlink():
        raise ValueError("fleet-agent must be a bundled executable, not a symlink")
    if agent.stat().st_size > MAX_AGENT_BYTES:
        raise ValueError("fleet-agent exceeds its 16 MiB client budget")
    jobs = bundle / "Contents/Library/LaunchAgents"
    if {path.name for path in jobs.iterdir()} != {"com.fleetconsole.fleetd.plist"}:
        raise ValueError("the bundle may register only fleetd; inference must stay opt-in")
    for path in bundle.rglob("*"):
        if path.suffix.lower() in MODEL_SUFFIXES or path.name in INFERENCE_BINARIES:
            raise ValueError(f"inference runtime or model weights cannot ship in FleetConsole: {path}")


if __name__ == "__main__":
    try:
        verify(sys.argv[1])
    except (ValueError, OSError, IndexError) as error:
        print(f"fleet-agent bundle rejected: {error}", file=sys.stderr)
        raise SystemExit(1)
