# Runbooks

A runbook is a versioned document that says what a model is allowed to do about
one situation: the symptom it addresses, the evidence to gather, the ordered
steps, which of those need a human, and when to stop and hand back.

It is the part of the agentic layer that is actually the product. The model is
interchangeable and getting cheaper; what makes a general model useful about a
port conflict at 3am is a paragraph written by somebody who has debugged one.
That paragraph is the `briefing`, and it is the reason a runbook is worth
shipping at all.

Nothing executes a runbook yet. This is the format, its linter, and the three
documents written in it.

## The one decision everything follows from

**A step is a typed action from a closed vocabulary, never a command string.**

The obvious design is `command: String` with the model filling in the blanks.
That design is a remote shell with extra steps: the blast radius is whatever the
model can spell, and no amount of prompting narrows it.

Here the set of things any runbook can express is fixed by `RunbookAction` at
compile time. The worst a malicious or merely confused document can ask for is
something already on the list — and everything on the list goes through
`fleetctl`, so leases, reaping and the event log apply to it unchanged. The
agentic layer inherits the controller's safety rail rather than needing one of
its own.

The cost is real and worth stating: a situation nobody anticipated cannot be
automated until the vocabulary grows, and growing it is a code change with a
review. That is the trade, and it is the right way round for software that
touches other people's machines.

## Layout

| File | Role |
| --- | --- |
| `FleetCore/Runbook.swift` | The format. Pure data — parameters, evidence, targets, actions, steps, stops |
| `FleetCore/RunbookValidation.swift` | The linter. Every rule rejects a shape a plausible author would write by accident |
| `FleetCore/RunbookLibrary.swift` | The three documents that ship, declared in Swift so the compiler and the suite check them |

`Codable` throughout, so exporting these as JSON documents — and loading
somebody else's — is a transport change rather than a format change.

## The vocabulary

**Evidence** is read-only by construction: `managedServices`,
`listenersOnPort`, `processTable`, `diskUsage`, `reclaimCandidates`,
`recentEvents`, `serviceLog`. Gathering it changes nothing, which is what lets
the whole diagnosis phase run without an approval gate.

**Actions** are `observe`, `stopService`, `renewLease`, `restartService`,
`reclaim` and `handOff`. `isReadOnly` switches exhaustively over them on
purpose: a new action must be classified deliberately rather than inheriting a
default.

**Targets** are `parameter(name)` — exactly the one service that was named — or
`each(query, max:)`. There is no "everything" case and there never will be. The
cap on `each` is mandatory, because an uncapped multi-target mutation is the
shape that stops a whole fleet from one bad match.

**Reclaim scope has exactly one rung**, `regeneratesFreely`. Everything else the
storage scanner finds — a model weight, a photo library, anything that does not
come back on its own — is reported to the operator and never offered to a
runbook. A ceiling with a second rung would eventually be raised, by a
well-meaning author, in a document nobody re-read.

## The linter

A runbook arrives as data, eventually from outside this repository, shipped
beside a model by someone who is not in the room. The type system stops it asking
for an action that does not exist. The linter stops the rest.

A **critical** refuses the document. A **warning** loads it and tells the author.

| Rule | Severity | Why |
| --- | --- | --- |
| A mutation with `automatic` approval | critical | The rule the format exists for |
| A mutation with no rationale | critical | An approval prompt nobody can reason about is one they learn to click through |
| `each` capped at 0, or above `maxTargets` (10) | critical | Zero hides a mistake; above ten the approval list stops being read |
| A reference to an undeclared parameter | critical | Including one nested inside a query, which is the one an author forgets |
| Acting on services without declaring `targetUnmanaged` | critical | See below |
| An unknown `formatVersion`, no steps, duplicate step ids | critical | A reader that guesses at a schema guesses wrong about an action's meaning eventually |
| Approval on a step that changes nothing | warning | Not dangerous, corrosive |
| A declared parameter nothing consumes | warning | Asking implies the answer mattered |
| A sweep with no `tooManyTargets` stop | warning | |
| A `stop` or `handOff` with no reason | warning | The event log will not explain itself later |

**`targetUnmanaged` is the one stop that is not a matter of taste.** Nothing in
this product signals a process the controller did not start, and a runbook that
does not say what it does when the culprit turns out to be somebody else's has
not thought about the case that matters most.

The rule is scoped precisely to runbooks that act on services. A document that
only clears caches has no target that could be unmanaged, and is not asked to
declare a stop that cannot occur — a rule that fires where it does not apply is
a rule authors learn to work around.

## The three

Three, and no more until these have been run against real machines. A format
proves nothing until something real is written in it, and the fastest way to end
up with a format that fits nothing is to design a fourth situation before the
first three have been used.

**`port-conflict`** — a port that will not bind is one of three things needing
opposite responses: a live service nobody remembered, an orphan whose agent went
away, or something that was never ours. The registry is what tells them apart,
so it is read before the process table. The stop is capped at one match, because
exactly one managed service can hold a port and two means the registry disagrees
with the machine.

**`leaked-daemon`** — a lapsed lease is the mechanism working, not a problem.
What makes it worth a runbook is the case where the lease lapsed because the
*agent* died rather than the work finishing. The event log separates an owner
that crashed from one that exited cleanly and left this up on purpose. Capped at
five.

**`disk-filling`** — one symptom, two causes that must never be treated the same
way. Caches regenerate; data does not, and a directory being large is not a
reason to delete it. This runbook can only touch the first kind, and that is not
a policy it can be talked out of. If the space went into real data the honest
ending is to say where and stop: what the operator's data is worth is theirs to
decide, not a model's.

## Testing

`Tests/FleetCoreTests/RunbookTests.swift` (28 tests) covers both halves. Every
linter rule gets a test that writes the bad shape on purpose, starting from a
fixture with no defects so a failure names its own cause. The three shipped
documents are asserted **clean, not merely loadable** — a warning in a shipped
runbook is one nobody will action, and it teaches the next author that warnings
are decoration.

Two assertions guard the format itself rather than a document: that
`RunbookReclaimScope` still has exactly one case, and that every mutation in the
library still requires approval — stated directly against the library so that a
regression in the linter cannot hide a regression in what ships.

## What is not here yet

Execution. `RunbookEngine` does not exist; neither does loading a document from
disk, nor the approval sheet, nor the record of what one run did. Those are the
next three steps, in that order, and the read-only diagnosis pass comes first
because it is the whole product demo and risks nothing.

`Runbook.diagnosis` and `Runbook.mutations` are derived rather than declared, so
when the engine arrives it cannot disagree with the document about which steps
are safe to run unattended.
