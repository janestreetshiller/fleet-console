# Multi-device and Ouros

Local monitoring is free. Multi-device access costs $10 USD per month through
Ouros, with one subscription and no per-device surcharge or included AI credit.

Connect your Ouros account in Devices. Opening Devices while signed out stays
local; Connect and Refresh explicitly contact `ouros.md`. A connected account
refreshes its subscription when Devices opens or the app becomes active.
The app opens the provider's existing
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

The device screen opens Ouros billing for prepaid AI credits. In Agents, Ouros Agent uses that same connected account to review current problems through `/ouros/v1/models` and `/v1/chat/completions`. Gateway access and balance checks govern inference; the multi-device subscription does not grant model credit or replace Ouros software access.

A review sends the problem report and relevant service records to the gateway. Read-only service tools use that supplied snapshot. Restart proposals need separate operator confirmation and use the existing controller, which refuses signalling authority over claimed processes. Requests are bounded to four model rounds and eight tool calls per round; opaque provider tool metadata survives subsequent rounds. An uncertain or canceled request is not automatically retried. Charges and elapsed time appear in the review sheet. Deployable agents and FleetConsole MCP remain planned.
