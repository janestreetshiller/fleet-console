# Multi-device and Ouros

Local monitoring is free. Multi-device access costs $10 USD per month through
Ouros, with one subscription and no per-device surcharge or included AI credit.

Connect your Ouros account in Devices. The app opens the provider's existing
browser approval flow and stores the resulting account session in macOS Keychain.
Approve only the code displayed by FleetConsole. Secure checkout uses the
server-owned monthly USD price. Opening checkout does not unlock the feature;
refreshing the subscription reads its paid entitlement. A canceled subscription
continues through its paid period, while expired, unpaid and past-due states do
not enable new device links. Disconnect removes this Mac's stored account session.

The FleetConsole subscription is separate from Ouros Pro. It does not replace a
Pro subscription, reset usage, grant credit, or change the existing credit catalog.
The provider checks canonical Stripe customer, subscription, price, invoice and
period data. Checkout operations are persisted in the existing private account
event store and reused across lost responses. Unknown outcomes are not silently
recreated after provider idempotency retention. Existing signed webhook checks
remain in place; FleetConsole events cannot overwrite the Pro subscription record.

Device linking changes only the local configuration's devices array, preserving
unrelated and unknown fields. The controller activates changes through its
existing reload operation. Link completion and reachability remain separate:
ICMP, TCP and SSH are checked independently. Optional inventory reads use existing
SSH configuration; passwords are never stored. Remote process control remains
read-only. Unlinking removes only that computer's configuration entry.

The device screen also opens Ouros billing for AI credits. Credit-funded inference,
supervised repair jobs, deployable agents and FleetConsole MCP remain future work.
No subscription credit allowance or automatic computer repair is promised.
