# FleetConsole launch copy

## Short post

FleetConsole helps you keep track of the servers your coding agents leave running. Launch through `fleetctl` with an owner and a lease; the controller cleans up unpaused services when their leases expire. You get CPU and memory dials in the menu bar and a full dashboard for the history or service logs.

## Release announcement

FleetConsole gives you a read of your Mac and a record of the services your agents start. Quick View shows CPU and memory dials in the menu bar, with network rates and service counts. Open the dashboard to see the history, inspect a process or read a service's logs and health-check results.

Launch agent work through `fleetctl` to record its owner and purpose, with a lease for how long it should run. Renew the lease while you need the service; the local controller stops unpaused services when time runs out. You can pause, resume, renew and stop controller-launched services from the app. Pausing preserves the process group and its resources, and suspends expiry cleanup until the service resumes.

FleetConsole source is MIT licensed. Local monitoring and controller tools are free to use. Connect your Ouros account for optional multi-device access at $10 USD/month, with remote metrics and read-only service inventory over SSH.

## Copy review

Grade: 9/10 for directness, specificity and accurate scope; this is an editorial judgment rather than a runtime metric.

The final copy describes the implemented quick-view/dashboard split, names the actual service workflow and separates free local tools from optional paid remote access. The review checked native views, lease cleanup, app controls, MIT terms, subscription price and SSH probes. Performance superlatives and future-feature promises stay outside the announcement; resource measurements belong in the assessment alongside their workload.
