# Swift 6 migration

All four targets moved from `.swiftLanguageMode(.v5)` to `.v6`. This is the
record of what the strict-concurrency checker actually found, kept because most
of it is not obvious from the diff: several changes look like annotations and are
in fact bug fixes, and two look like bug fixes and are in fact deliberate refusals
to change behaviour.

Verified at the end of the migration: clean debug build and clean **release**
build (35 s from scratch, zero warnings and zero errors from our sources), 42
tests passing, `Scripts/design-audit.sh` clean.

## What each target cost

| Target | Errors | Warnings | Notes |
|---|---|---|---|
| `fleetctl` | 0 | 0 | Nothing. Top-level code in an executable target is implicitly `@MainActor` under v6, which is what it always was in practice. |
| `fleetd` | 0 | 3 | Compiled unchanged. The warnings were real — see *Genuine races* below. |
| `FleetCore` | 2 | 2 | Both errors were shared formatters; both warnings were lock-protected boxes that had never said so. |
| `FleetConsoleApp` | 9 | 3 | The bulk of it, and mostly AppKit isolation that was previously convention. |

## Genuine races the v5 compiler could not see

**`DaemonClient.shouldRun`** — a plain `Bool`, written by `stop()` on the main
thread and read on every pass of the subscription thread's reconnect loop. It is
the only thing that ends that loop, so a missed write is a thread that never
stops. Now behind a lock.

**The daemon's broadcast block** (`Controller.dispatchBroadcast`) — the block
reached through `[weak self]` five separate times. Each `self?` is its own load,
so a controller torn down mid-broadcast could drop a subscriber and then fail to
clear `broadcastInFlight`, leaving the daemon believing a broadcast was still in
flight and never sending another. Binding once at the top makes the block
all-or-nothing.

**`OrcsInvocation`'s termination handler** — the same double-load shape, plus
`process.terminationStatus` being read from the queue block rather than from the
handler that owns the process. Both fixed by binding once and reading the status
eagerly.

**`Controller.onRejectedPeer`** — same double-load. The log line stays
unconditional; only the registry write is guarded.

## Where an annotation was the honest answer

`@unchecked Sendable` is used five times, and in each case the safety argument is
written at the declaration rather than assumed:

- **`SocketConnection`** — two *different* disciplines, which is why it needed
  spelling out: `buffer` is confined to the single thread the server starts per
  accepted connection, while `closed` and every write are serialised by
  `writeLock`, because the broadcast path writes while that owning thread is
  parked in `read`.
- **`Controller`** — the serial state queue described in the type's own doc
  comment. The annotation states that contract; it does not relax it.
- **`FleetLog`** — `fileHandle` inside its queue, `minimumLevel` behind its own
  lock. It gets a second lock rather than riding the file queue because the level
  check is the fast path: routing a filtered debug line through `queue.sync`
  would put it on the very queue it is trying not to touch. An actor would be
  tidier and wrong — `FleetLog` is called from `deinit` and from teardown paths
  that cannot suspend.
- **`DrainedOutput`**, **`HealthChecker.SettledOutcome`** — already
  fully lock-protected; they simply had never declared it.

`nonisolated(unsafe)` appears three times, all of them the same situation:
`NotificationCenter` observer tokens whose existential type is not `Sendable`,
written on the main thread in `init` and read in `deinit` — which is nonisolated
under Swift 6 and therefore cannot see main-actor state.

## Where the modern API was measured and rejected

**`ByteCountFormatter` stays.** The obvious fix for a shared mutable formatter is
`ByteCountFormatStyle`, a `Sendable` value. It was tried and reverted: it renders
kilobytes as **"kB"** where this app has always shown **"KB"**. That is every
storage row and transfer rate in the window changing its text, and a concurrency
migration is not a licence to change what the app reads. The formatter is kept
and the *sharing* is made safe instead, via a small locked wrapper —
`SharedByteFormatter`, which also collapsed two identically-configured private
formatters (`ConsoleFmt` and `SystemFmt`) into one.

**`ISO8601DateFormatter` goes.** The opposite call, for the opposite reason:
`Date.ISO8601FormatStyle` parses tailscale's two RFC 3339 shapes identically, so
there was no behaviour to preserve — only shared mutable state to delete.
`TailscaleDateTests` pins the contract that swap has to keep, including Go's zero
`time.Time` still reading as "never seen" rather than as a year-1 date.

**`vm_kernel_page_size` goes.** Replaced with `host_page_size()`, which is not a
workaround: it is the documented pairing for the `host_statistics64` counts being
multiplied by it, where the global was merely the value that happened to be
lying around. Both report 16384 here; the point is which one is *defined* to
match.

## Deprecations that only fire under v6

`String(cString:)`'s array overload is deprecated in language mode 6 and silent
in mode 5 — confirmed by compiling the same file both ways. Two call sites in the
app and one in the daemon needed it, so the replacement lives in FleetCore as
`String(nulTerminated:)` rather than once per target. Only the array overload is
affected; the pointer overload used elsewhere is fine.

## Not done

`HealthChecker.httpGet` still blocks a `workQueue` thread on a semaphore for the
duration of each check. Its data race is fixed, but `async`/`await` would remove
the blocking too, and that is a behavioural change to the daemon's threading —
deliberately not bundled into a language-mode migration. It also still has no
regression test, because `fleetd` is an executable target with nothing able to
import it.
