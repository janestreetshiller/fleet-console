import Foundation

// The runbooks that ship with the app.
//
// Three, and no more until these three have been run against real machines. A
// format proves nothing until something real is written in it, and the fastest
// way to end up with a format that fits nothing is to design a fourth situation
// before the first three have been used.
//
// They are declared here rather than loaded from JSON so the compiler checks
// them and the test suite validates them on every run. The type is `Codable`
// throughout, so exporting these as documents — and loading somebody else's —
// is a transport change, not a format change.
//
// **The briefing is the product.** The model is interchangeable; what makes it
// useful about a port conflict at 3am is a paragraph from someone who has
// debugged one. Each briefing below is written to be read by a model that knows
// how computers work and nothing whatsoever about this machine.

public enum RunbookLibrary {

    public static let all: [Runbook] = [portConflict, leakedDaemon, diskFilling]

    public static func runbook(id: String) -> Runbook? {
        all.first { $0.id == id }
    }

    // MARK: - Port conflict

    public static let portConflict = Runbook(
        id: "port-conflict",
        revision: 1,
        title: "A port is already in use",
        symptom: "Something will not start because its port is taken.",
        briefing: """
            A port that will not bind is almost always one of three things, and \
            they need opposite responses.

            It may be a service this controller owns and nobody remembered — the \
            lease is alive, the process is healthy, and it is simply still doing \
            what it was asked to do last week. It may be a service whose owning \
            agent has gone away, in which case the process is orphaned and \
            stopping it costs nothing. Or it may not be ours at all: Docker, a \
            system daemon, another user's process.

            Only the first two are yours to stop, and the registry is what tells \
            them apart — so read it before the process table, not after. An \
            owned service comes with an owner and a stated purpose, which is the \
            difference between "stop it" and "go and ask the person who started \
            it". If the holder is not in the registry, that is the end of the \
            runbook: this product does not signal a process it did not start, \
            and the operator needs to know who does own it, not to be offered a \
            button.
            """,
        parameters: [
            RunbookParameter(name: "port", kind: .port,
                             prompt: "Which port is refusing to bind?")
        ],
        evidence: [
            .listenersOnPort(parameter: "port"),
            .managedServices
        ],
        steps: [
            RunbookStep(
                id: "who-holds-it",
                title: "Find what is listening on the port",
                action: .observe(.listenersOnPort(parameter: "port")),
                rationale: "The pid and the command name are what every later step turns on.",
                approval: .automatic),
            RunbookStep(
                id: "is-it-ours",
                title: "Check the port against the controller's registry",
                action: .observe(.managedServices),
                rationale: "A holder in the registry has an owner and a purpose; one that is "
                    + "not is somebody else's process and is not ours to stop.",
                approval: .automatic),
            RunbookStep(
                id: "stop-the-holder",
                title: "Stop the managed service holding the port",
                action: .stopService(.each(.listeningOnPort(parameter: "port"), max: 1),
                                     reason: "Freeing the port for a new bind"),
                rationale: "Exactly one managed service can hold a port. If two match, the "
                    + "registry disagrees with the machine and a human should look.",
                approval: .operatorApproval),
            RunbookStep(
                id: "hand-back",
                title: "Report who holds the port",
                action: .handOff(reason: "The port is held by a process the controller did not "
                                 + "start. Here is what is holding it and who it belongs to."),
                rationale: "Ending with the answer is more use than ending with a refusal.",
                approval: .automatic)
        ],
        stopWhen: [.targetUnmanaged, .tooManyTargets, .evidenceUnavailable, .approvalDenied])

    // MARK: - Leaked daemon

    public static let leakedDaemon = Runbook(
        id: "leaked-daemon",
        revision: 1,
        title: "An agent left something running",
        symptom: "A background process is still up after the agent that started it went away.",
        briefing: """
            A lease is a promise to keep saying "still needed". The controller \
            reaps what stops saying it, so a lapsed lease is not by itself a \
            problem — it is the mechanism working.

            What makes this worth a runbook is the case where the lease lapsed \
            because the *agent* died rather than the work finishing. Then the \
            service is orphaned: nothing will renew it, nothing is reading its \
            output, and it will hold its port and its memory until something \
            stops it. That is different from a service whose agent exited \
            cleanly and deliberately left it up, which is rare but real.

            The event log tells them apart. An owner with a crash or a reap in \
            its recent history left this behind by accident. An owner that \
            stopped its other services cleanly and left this one did it on \
            purpose — and stopping it is then a decision, not a cleanup.

            Sweep conservatively. Five at once is already more than an operator \
            reads carefully.
            """,
        evidence: [
            .managedServices,
            .recentEvents(limit: 20)
        ],
        steps: [
            RunbookStep(
                id: "expired-leases",
                title: "List services whose lease has lapsed",
                action: .observe(.managedServices),
                rationale: "The candidate set. Everything else narrows it.",
                approval: .automatic),
            RunbookStep(
                id: "how-the-owner-left",
                title: "Read what the owning agents did last",
                action: .observe(.recentEvents(limit: 20)),
                rationale: "An owner that crashed left this by accident; one that stopped its "
                    + "other services cleanly left it on purpose.",
                approval: .automatic),
            RunbookStep(
                id: "stop-the-orphans",
                title: "Stop the orphaned services",
                action: .stopService(.each(.leaseExpired, max: 5),
                                     reason: "Lease expired and the owning agent is gone"),
                rationale: "Capped at five because the approval list is the control, and a "
                    + "list nobody finishes reading is not one.",
                approval: .operatorApproval)
        ],
        stopWhen: [.targetUnmanaged, .tooManyTargets, .approvalDenied, .stepFailed])

    // MARK: - Disk filling

    public static let diskFilling = Runbook(
        id: "disk-filling",
        revision: 1,
        title: "The disk is filling up",
        symptom: "Free space is running low and something needs to go.",
        briefing: """
            A full disk is one symptom with two causes that must never be \
            treated the same way.

            Caches regenerate. Deleting a package cache or a build directory \
            costs you a slower next build and nothing else. Data does not \
            regenerate: a model weight is an hour of bandwidth, a photo library \
            is irreplaceable, and a directory being large is not a reason to \
            delete it. A cleaner that cannot tell those apart is not a tool, it \
            is a trap.

            This runbook is only ever allowed to touch the first kind. That is \
            not a policy you can talk it out of — the scope is fixed in the \
            format and there is no second setting. If the space has gone into \
            real data, the honest end to this runbook is to say exactly where it \
            went and stop. What the operator's data is worth is theirs to decide \
            and nobody else's, least of all a model's.
            """,
        evidence: [
            .diskUsage,
            .reclaimCandidates
        ],
        steps: [
            RunbookStep(
                id: "where-it-went",
                title: "Measure the volume and what is on it",
                action: .observe(.diskUsage),
                rationale: "How much is actually needed decides whether caches are enough.",
                approval: .automatic),
            RunbookStep(
                id: "what-regenerates",
                title: "Find the space that comes back on its own",
                action: .observe(.reclaimCandidates),
                rationale: "Separates what is safe to lose from what only looks large.",
                approval: .automatic),
            RunbookStep(
                id: "clear-caches",
                title: "Delete caches that regenerate",
                action: .reclaim(.regeneratesFreely),
                rationale: "The only deletion this product will make on anyone's behalf: "
                    + "everything here comes back without being fetched again.",
                approval: .operatorApproval),
            RunbookStep(
                id: "hand-back",
                title: "Report what is left",
                action: .handOff(reason: "If the disk is still tight, what remains is your "
                                 + "data. Here is where it went; deciding what it is worth "
                                 + "is yours."),
                rationale: "The runbook stops at the boundary of what it is allowed to judge.",
                approval: .automatic)
        ],
        stopWhen: [.evidenceUnavailable, .approvalDenied, .stepFailed, .exhausted])
}
