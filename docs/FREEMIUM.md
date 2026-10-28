# Legacy freemium model

**Historical reference only.** The current MIT build permanently unlocks every
feature, including SMC sensors, advanced filters, welcome skipping and reconcile.
Trial records and offline key parsing remain compatible with older installs but
never control feature access. There is no checkout or donation requirement.

The honest scaffolding, as it stands (2026-10-05). There is a trial clock, a
key format with real signature checking, and one gate that answers "is this
feature premium". There is deliberately no checkout, no network validation and
no revocation list. `FleetCore/License.swift` says so itself.

## The gate

`PremiumFeature` lists what a licence unlocks; everything not listed is free
forever. The free tier can *see* reconciler drift (the overview shows
mismatches as they happen); only a trial or a licence can *apply* desired state
(`fleetctl reconcile` / the console's reconcile action are premium).

| Feature | Free | Trial/licensed |
|---|---|---|
| Everything not below | ✓ | ✓ |
| SMC fan & temperature sensors | — | ✓ |
| Skip welcome animation | — | ✓ |
| Advanced heatmap filters | — | ✓ |
| Reconcile — apply desired state | read-only drift view | ✓ |

## Trial

14 days from first launch, persisted in UserDefaults. It is a clock, not a
defence — rolling it back costs nothing to defend and is not worth defending.

## Key format

`FLT1-<base32 payload>.<base32 HMAC-SHA256>`. Payload is the ISO-8601 issue
date; the signature is HMAC-SHA256 over the payload with the vendor secret.
Validation is offline and deterministic — a key that validates today validates
in ten years. `FLT2` can change everything after the dash without breaking old
keys. The signing secret lives in the source on purpose (scaffolding); obscurity
is not the defence described in the threat model.

## Minting (the Ouros path)

Keys are minted offline, never by the app, never over the network:

```bash
fleetctl license --secret <vendor secret> [--date 2026-10-05]
```

`FLEET_LICENSE_SECRET` works instead of the flag. A store webhook — or the
Ouros bar on the user's behalf — shells out to this, prints a key, and the user
pastes it into the app. The same locality argument as the rest of the product
applies: Ouros already reaches this machine's Unix socket for the agent
mailbox, so the freemium wire adds no new listener, no telemetry, and no cloud. A
mismatched mint still fails at the gate, because the app validates with its own
copy of the secret.

## Not built (and why)

- No checkout. `fleetctl license` is a seam; the store side is Ouros.
- No network validation. Keys validate offline forever.
- No revocation. The threat model says entropy is the adversary, not pirates;
  defending the key stops nobody and costs the honest user.
