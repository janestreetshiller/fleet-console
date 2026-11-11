# Install a reviewed prebuilt Fleet Console

`Scripts/update-installed.sh <git-ref>` keeps its existing clean-source build behavior. Its explicit `--prebuilt` mode installs the exact verified artifact on another Mac without copying signing credentials.

After the normal Developer ID build, notarization and installed-source checks, prepare the transfer in a fresh owning artifact directory:

```sh
python3 Scripts/prepare-prebuilt.py --bundle '/Applications/FleetConsole.app' \
  --source-revision '<full-reviewed-source-revision>' \
  --core-sha256 '<reviewed-core-sha256>' --team '<reviewed-Developer-ID-team>' \
  --output "$PWD/artifacts/portable/<fresh-directory>"
```

Retain the printed handoff and tool hashes separately. Transfer the complete directory. On the receiving Mac, verify those hashes, then record and review its actual predecessor:

```sh
python3 Scripts/verify-core-update.py --snapshot '/Applications/FleetConsole.app' > '<fresh-predecessor.json>'
FLEETCONSOLE_PREBUILT_APP='<absolute-transfer-directory>/FleetConsole.app' \
FLEETCONSOLE_PREDECESSOR_PROOF='<absolute-reviewed-predecessor.json>' \
FLEETCONSOLE_EXPECTED_CORE_SHA256='<reviewed-core-sha256>' \
FLEETCONSOLE_EXPECTED_TEAM='<reviewed-Developer-ID-team>' \
bash Scripts/update-installed.sh '<full-reviewed-source-revision>' --prebuilt
```

The existing updater verifies Developer ID, the stapled ticket, Gatekeeper, clean source metadata and the actual executable's core before replacement. It checks the exact installed predecessor before quitting the client and again before replacement. The previous app is retained for rollback; `fleetd` and its managed services keep running. Do not pass `--restart-controller` for a client-only update. The separate installed GUI acceptance remains required.
