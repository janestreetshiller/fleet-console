#!/usr/bin/env python3
"""Run native terminal/Overview acceptance with every prerequisite supplied.

Uses the production Rust formatter and actual fleet-agent executable, but only a
labelled loopback HTTP fixture, never a model/provider or a paid investigation.
The shipping Overview uses observational RPC policy against the current daemon.
Captures may contain local process/telemetry data; keep the output private.
"""

import argparse
import json
import os
from pathlib import Path
import platform
import subprocess
import tempfile
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

ROOT = Path(__file__).resolve().parent.parent
QUESTION = "Explain the deterministic terminal rendering verification response."
REPLY = "Finding: 3 services healthy.\n\nEvidence: deterministic HTTP fixture.\n\nProposed action: none."


def run(command, log, *, env=None):
    print("Running:", " ".join(map(str, command)), flush=True)
    with log.open("w") as output:
        result = subprocess.run(command, cwd=ROOT, env=env, stdout=output,
                                stderr=subprocess.STDOUT, timeout=600)
    if result.returncode:
        raise RuntimeError(f"Command exited {result.returncode}; inspect {log}")
    print(f"Passed; log: {log}", flush=True)


def tool_output(*command):
    return subprocess.check_output(command, cwd=ROOT, text=True).strip()


class FixtureHandler(BaseHTTPRequestHandler):
    def log_message(self, *_args):
        pass

    def do_POST(self):
        length = int(self.headers.get("Content-Length", "0"))
        if self.path != "/v1/chat/completions" or not 0 < length <= 128 * 1024:
            self.send_error(400, "Only the bounded TEST DATA proposal is allowed")
            return
        try:
            request = json.loads(self.rfile.read(length))
            if request["messages"][-1]["content"] != QUESTION:
                raise ValueError("Unexpected TEST DATA question")
        except (ValueError, KeyError, IndexError, TypeError):
            self.send_error(400, "Unexpected TEST DATA request")
            return
        self.server.observed_requests.append({"method": "POST", "path": self.path})
        # Preserve a visible preparing state before the deterministic reply.
        time.sleep(1)
        body = json.dumps({"choices": [{"message": {"role": "assistant", "content": REPLY}}]}).encode()
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, help="Fresh private output directory (default: system temp)")
    args = parser.parse_args()
    if platform.system() != "Darwin":
        parser.error("Native acceptance requires macOS and the installed Xcode toolchain")
    if args.output:
        args.output.mkdir(mode=0o700, parents=True, exist_ok=False)
        output = args.output.resolve()
    else:
        output = Path(tempfile.mkdtemp(prefix="fleet-terminal-integration-")).resolve()
    print(f"Private evidence: {output}", flush=True)
    fixtures = output / "formatter"
    env = dict(os.environ, FLEET_AGENT_PRESENTATION_EVIDENCE_DIR=str(fixtures))
    run(["cargo", "test", "--manifest-path", "rust/Cargo.toml", "--locked", "--jobs", "2",
         "-p", "fleet-agent", "terminal_labels_leave_reply_and_error_bytes_intact"],
        output / "rust-formatter.log", env=env)
    for name in ("short", "wrapped", "controls", "error"):
        if "TEST DATA:" not in (fixtures / f"{name}.ansi").read_text():
            raise RuntimeError(f"Production formatter did not generate labelled {name} fixture")
    run(["cargo", "build", "--manifest-path", "rust/Cargo.toml", "--locked", "--jobs", "2",
         "--bin", "fleet-agent"], output / "rust-build.log")
    metadata = json.loads(tool_output("cargo", "metadata", "--manifest-path", "rust/Cargo.toml",
                                      "--locked", "--no-deps", "--format-version", "1"))
    agent = Path(metadata["target_directory"]) / "debug/fleet-agent"
    run(["swift", "build", "--build-tests", "--disable-index-store", "--jobs", "2"],
        output / "swift-build.log")
    binary_dir = Path(tool_output("swift", "build", "--disable-index-store", "--show-bin-path"))
    bundle = binary_dir / "FleetConsoleAppTests.xctest/Contents/MacOS/FleetConsoleAppTests"
    swift_bin = Path(tool_output("xcrun", "--find", "swift")).parent
    helper = swift_bin.parent / "libexec/swift/pm/swiftpm-testing-helper"
    platform_dir = Path(tool_output("xcrun", "--sdk", "macosx", "--show-sdk-platform-path"))
    if not helper.is_file() or not bundle.is_file() or not agent.is_file():
        raise RuntimeError("Native runner, test bundle or actual agent is missing after the build")
    # SwiftPM normally supplies these when launching the helper. Invoke it
    # directly to add --verify-live, enabling the observational Overview test.
    native_env = dict(os.environ,
        DYLD_FRAMEWORK_PATH=str(platform_dir / "Developer/Library/Frameworks"),
        DYLD_LIBRARY_PATH=str(platform_dir / "Developer/usr/lib") + ":" + str(swift_bin.parent / "lib/swift/macosx"),
        FLEET_TERMINAL_FORMATTER_FIXTURES=str(fixtures),
        FLEET_TERMINAL_AGENT_BINARY=str(agent),
        FLEET_TERMINAL_EXPECT_AGENT_STYLE="1",
        FLEET_TERMINAL_EXPECTED_REPLY=REPLY,
        FLEET_TERMINAL_EVIDENCE_DIR=str(output / "terminal"),
        FLEET_OVERVIEW_CAPTURE_DIR=str(output / "overview"),
        FLEET_AGENT_SESSION_EVIDENCE_DIR=str(output / "sessions"))
    native_env.pop("FLEET_TEST_TERMINATION_NOTIFICATION", None)
    server = ThreadingHTTPServer(("127.0.0.1", 0), FixtureHandler)
    server.daemon_threads = True
    server.observed_requests = []
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    native_env["FLEET_TERMINAL_LLM_URL"] = f"http://127.0.0.1:{server.server_port}"
    try:
        logs = []
        # Suites share process-wide AppKit state; .serialized only serializes
        # cases within one suite. Isolate the native suites from each other.
        selections = [(suite, suite) for suite in
                      ("TerminalOutputTests", "TerminalAgentSessionTests", "OverviewViewportTests")]
        selections.append(("TerminationNotification", "TerminalAgentSessionTests/quitWaitsForCleanup"))
        for name, selection in selections:
            log = output / f"{name}.log"
            logs.append(str(log))
            case_env = dict(native_env)
            if name == "TerminationNotification":
                case_env["FLEET_TEST_TERMINATION_NOTIFICATION"] = "1"
            run([str(helper), "--test-bundle-path", str(bundle), "--testing-library", "swift-testing",
                 "--filter", selection, "--verify-live"], log, env=case_env)
            text = log.read_text()
            if "skipped" in text or "Test run with" not in text or "Test run with 0 tests" in text:
                raise RuntimeError(f"Acceptance must actually run without skipped cases; inspect {log}")
        if len(server.observed_requests) != 1:
            raise RuntimeError(f"Expected exactly one owned fixture request, got {server.observed_requests}")
    finally:
        server.shutdown()
        server.server_close()
        thread.join(timeout=2)
    (output / "acceptance.json").write_text(json.dumps({
        "sourceRevision": tool_output("git", "rev-parse", "HEAD"),
        "sourceDirty": bool(tool_output("git", "status", "--porcelain")),
        "modelInference": False,
        "paidProviderRequests": False,
        "daemonPolicy": "observational",
        "fixtureRequests": server.observed_requests,
        "nativeTestLogs": logs,
    }, indent=2) + "\n")
    print(f"All native acceptance cases passed without skips. Evidence: {output}")


if __name__ == "__main__":
    main()
