# Multi-device and Ouros

Owner direction, October 11, 2026: local monitoring stays free. The multi-device
add-on is $10 USD per month through Ouros. This is one multi-device subscription;
no per-device surcharge, device-count limit or included AI credit is asserted.

The current review build supports real device linking and unlinking. Both update
only the devices array in the local configuration, preserve unknown fields, and
activate through the existing `reloadConfig` RPC. Linking does not establish
reachability: ICMP, TCP and SSH results remain separate evidence. Remote services
are read-only. Existing SSH configuration supplies credentials; the UI never
stores passwords. First-run setup lists only the actual local computer.

The device screen opens the existing Ouros Billing page, where prepaid AI credits
are managed. Its $10/month FleetConsole offer and entitlement are not active.
The inspected Ouros catalog currently exposes its $19/month Pro offer and optional
one-time credit packs; it contains no FleetConsole product. FleetConsole must not
sell that Pro offer as its own multi-device subscription.

## Provider activation contract

The provider needs a FleetConsole offer for a recurring USD subscription of
1000 cents per month, with a separate product entitlement. A suggested internal
identifier is `fleet-console-multi-device`; it is not a registered provider SKU.
Checkout must come from the server's authenticated billing catalog, using the
existing idempotency and signed fulfillment paths. The app must accept an
account-bound provider entitlement, cancellation and expiration rather than
revive the legacy source-embedded HMAC key. No local key or receipt currently
claims an active subscription. Linking remains a preview until this integration
is activated.

## AI credits and supervised jobs

Existing Ouros prepaid credits are separate from subscriptions. No monthly credit
allowance is promised. FleetConsole has a local Interpret tool today, using the
existing `orcs` wrapper; it does not debit Ouros credits. Credit-funded inference,
trained repair agents, deployable agents and a FleetConsole MCP remain planned.
A production job path needs authenticated balance checks, an explicit spending
limit, idempotent execution and settlement, recorded results, and a human-approved
repair scope. Metered execution must stop at zero credit. Process ownership,
leases, PID identity checks and the controller's signal boundary continue to
apply to agent jobs.

The provider catalog and job routes were inspected read-only. No provider product,
purchase, customer entitlement, account balance or deployment was changed.
