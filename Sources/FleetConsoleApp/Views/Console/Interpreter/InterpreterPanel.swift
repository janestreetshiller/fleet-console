import SwiftUI
import FleetCore

// The local-model interpreter panel.
//
// One page, one model, one question at a time. The panel:
//   1. Checks what `orcs` can do (`orcs models`) when it is first opened.
//   2. Offers only the presets the installed models can satisfy.
//   3. Assembles a prompt from the controller's current snapshot and shows it
//      so the operator can read exactly what the model was told.
//   4. Runs `orcs debug`/`code`/`review`/`plan` as a one-shot child and streams
//      its answer into the text area.
//   5. Keeps the scrollback from the last request across panel toggles.
//
// Non-goals that are also rules:
//   - This panel never starts a server, never binds a port and never manages a
//     model lifecycle. `orcs` handles all of that internally.
//   - Environment values are never in the prompt — only the keys. The registry
//     does not store them; the assembler enforces the same rule.
//   - An answer the operator cannot audit is not evidence. The prompt inspector
//     shows everything the model was given, in the order it was given.

// MARK: - Panel model

/// All mutable state for the interpreter panel.
/// Lives on `@MainActor` so there is no cross-actor coordination inside view callbacks.
@MainActor
@Observable
final class InterpreterModel {
    // MARK: Inventory
    var inventory: Result<[OrcsModel], OrcsProbingError>?
    var isCheckingInventory = false

    // MARK: Preset selection
    var selectedPreset: InterpreterPreset = .default

    // MARK: Run state
    enum RunState: Equatable {
        case idle
        case assembling
        case running(seconds: Int)
        case done
        case failed(String)
    }
    var runState: RunState = .idle
    var streamingOutput = ""
    var promptInspector: AssembledPrompt?
    var modelBanner: String?
    var showingPrompt = false

    // MARK: Context
    var context = ToolContext()

    // MARK: Lifecycle
    private var runTask: Task<Void, Never>?
    private var elapsedTimer: Task<Void, Never>?
    private var runSeconds = 0

    var isRunning: Bool {
        if case .running = runState { return true }
        return false
    }

    var orcsBinaryPath: String? {
        Orcs.locate()
    }

    // MARK: Inventory probe

    func checkInventory() {
        guard !isCheckingInventory else { return }
        guard let binary = orcsBinaryPath else {
            inventory = .failure(OrcsProbingError(message: "`orcs` not found. Install it at \(Orcs.expectedPath) or anywhere in $PATH."))
            return
        }
        isCheckingInventory = true
        Task {
            let result = await OrcsInventory.probe(executable: binary)
            isCheckingInventory = false
            inventory = result
        }
    }

    func availability(for preset: InterpreterPreset) -> PresetAvailability {
        guard let inventory else { return .unknown }
        switch inventory {
        case .failure: return .unknown
        case .success(let models):
            if let match = preset.requirement.match(in: models) { return .available(match) }
            return .missingModel(requirement: preset.requirement.label, installed: models.map(\.name))
        }
    }

    // MARK: Run / cancel

    func run(preset: InterpreterPreset, context: ToolContext) {
        guard let binary = orcsBinaryPath else { return }
        runTask?.cancel()
        runTask = nil
        streamingOutput = ""
        modelBanner = nil
        promptInspector = nil
        runSeconds = 0
        runState = .assembling

        runTask = Task { [weak self] in
            guard let self else { return }
            // 1. Gather evidence from the controller.
            let evidence = await InterpreterEvidenceLoader.load(serviceID: context.serviceID)
            guard !Task.isCancelled else { return }

            // 2. Assemble the prompt.
            let prompt = PromptAssembler.assemble(preset: preset, context: context,
                                                  evidence: evidence)
            self.promptInspector = prompt
            guard !Task.isCancelled else { return }

            // 3. Start the elapsed timer.
            self.runState = .running(seconds: 0)
            self.startElapsedTimer()

            // 4. Exec orcs. Presets that pin their own model go through
            //    `orcs run -model …`; the escalations keep the verb alias.
            let resolvedModel: String
            switch self.availability(for: preset) {
            case .available(let model): resolvedModel = model.name
            default: resolvedModel = ""
            }
            let run = await OrcsProcess.run(
                executable: binary,
                arguments: preset.arguments(model: resolvedModel, prompt: prompt.text),
                workingDirectory: context.workingDirectory,
                timeout: Orcs.requestTimeout,
                onOutput: { [weak self] accumulated in
                    DispatchQueue.main.async {
                        self?.streamingOutput = accumulated
                    }
                },
                onDiagnostics: { [weak self] accumulated in
                    DispatchQueue.main.async {
                        self?.modelBanner = OrcsDiagnostics.banner(accumulated)
                    }
                }
            )
            guard !Task.isCancelled else { return }

            // 5. Settle.
            self.stopElapsedTimer()
            if run.succeeded {
                self.streamingOutput = run.stdout
                self.runState = .done
            } else {
                let reason = OrcsDiagnostics.failureLine(run)
                    ?? "orcs exited without an explanation"
                self.runState = .failed(reason)
            }
        }
    }

    func cancelRun() {
        runTask?.cancel()
        runTask = nil
        stopElapsedTimer()
        runState = .idle
    }

    // MARK: Private

    private func startElapsedTimer() {
        elapsedTimer?.cancel()
        elapsedTimer = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard let self, !Task.isCancelled else { return }
                self.runSeconds += 1
                if case .running = self.runState {
                    self.runState = .running(seconds: self.runSeconds)
                }
            }
        }
    }

    private func stopElapsedTimer() {
        elapsedTimer?.cancel()
        elapsedTimer = nil
    }

    // Tasks own themselves via reference counting, so we just nuke the references
    // and let Swift cancel them on the next cooperative yield. The tasks hold
    // only weak self, so there is no retain cycle here.
    nonisolated func cleanup() {
        // No-op: tasks are cancelled via cancelRun/stopElapsedTimer while live.
        // Called from the panel's deactivate, which is main-actor.
    }
}

// MARK: - ToolSurface conformance

@MainActor
final class InterpreterPanel: ToolSurface {
    let tool: ConsoleTool = .interpreter

    private let panelModel = InterpreterModel()

    var isLive: Bool { panelModel.isRunning }

    func activate(context: ToolContext) {
        panelModel.context = context
        panelModel.checkInventory()
    }

    func resize(to grid: TerminalGrid) {
        // The interpreter is not PTY-backed; it reflows freely.
    }

    func deactivate() {
        // Keep the last answer warm across toggles.
    }

    func makeView() -> AnyView {
        AnyView(InterpreterPanelView(model: panelModel))
    }
}

// MARK: - Root view

private struct InterpreterPanelView: View {
    @Bindable var model: InterpreterModel

    var body: some View {
        VStack(spacing: 0) {
            presetBar
            Hairline()
            if model.showingPrompt, let prompt = model.promptInspector {
                promptInspectorPane(prompt)
            } else {
                answerPane
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Preset bar

    /// Every preset, wrapped onto as many rows as the panel needs.
    ///
    /// This was a horizontal `ScrollView` with `showsIndicators: false`, which at
    /// the panel's usual width put three and a half of the five presets on
    /// screen: the fourth was sliced down its middle with no scrollbar, no fade
    /// and no other hint that it was scrollable, so it read as a clipped panel
    /// rather than as a scrollable one. A chooser has to show what there is to
    /// choose from — and with five short chips there is no reason to hide any of
    /// them behind a gesture.
    private var presetBar: some View {
        FlowLayout(spacing: 6) {
            ForEach(InterpreterPreset.all) { preset in
                PresetChip(
                    preset: preset,
                    availability: model.availability(for: preset),
                    isSelected: model.selectedPreset == preset
                ) {
                    model.selectedPreset = preset
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
    }

    // MARK: Answer pane

    private var answerPane: some View {
        VStack(spacing: 0) {
            // Status / run bar
            HStack(spacing: 8) {
                statusLabel
                Spacer(minLength: 4)
                if model.promptInspector != nil {
                    Button(action: { model.showingPrompt = true }) {
                        Label("Prompt", systemImage: "doc.text.magnifyingglass")
                            .font(ConsoleFont.caption)
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
                }
                if model.isRunning {
                    Button("Cancel", action: model.cancelRun)
                        .buttonStyle(.borderless)
                        .font(ConsoleFont.caption)
                        .foregroundStyle(StatusTone.bad.ink)
                } else {
                    let avail = model.availability(for: model.selectedPreset)
                    Button("Run") {
                        model.run(preset: model.selectedPreset, context: model.context)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(!avail.isAvailable || model.orcsBinaryPath == nil)
                    .help(avail.detail)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)

            Hairline()

            // Output / placeholder
            Group {
                if model.streamingOutput.isEmpty {
                    emptyAnswerState
                } else {
                    answerText
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var statusLabel: some View {
        Group {
            switch model.runState {
            case .idle:
                if let _ = model.orcsBinaryPath {
                    Label(model.selectedPreset.commandLabel, systemImage: model.selectedPreset.symbol)
                } else {
                    Label("`orcs` not found", systemImage: "exclamationmark.triangle")
                        .foregroundStyle(StatusTone.bad.ink)
                }
            case .assembling:
                Label("Gathering evidence…", systemImage: "arrow.down.circle")
                    .foregroundStyle(.secondary)
            case .running(let seconds):
                Label("Running · \(seconds)s", systemImage: "circle.dotted")
                    .foregroundStyle(.tint)
            case .done:
                if let banner = model.modelBanner {
                    Label(banner, systemImage: "checkmark.circle")
                        .foregroundStyle(StatusTone.good.ink)
                } else {
                    Label("Done", systemImage: "checkmark.circle")
                        .foregroundStyle(StatusTone.good.ink)
                }
            case .failed(let reason):
                Label(reason, systemImage: "xmark.octagon")
                    .foregroundStyle(StatusTone.bad.ink)
            }
        }
        .font(ConsoleFont.caption)
        .lineLimit(1)
        .truncationMode(.tail)
    }

    @ViewBuilder
    private var emptyAnswerState: some View {
        switch model.runState {
        case .idle:
            let avail = model.availability(for: model.selectedPreset)
            VStack(spacing: 10) {
                Image(systemName: model.selectedPreset.symbol)
                    .font(ConsoleFont.emptyGlyph)
                    .foregroundStyle(SurfaceInk.secondary)
                Text(model.selectedPreset.title)
                    .font(ConsoleFont.subtitle.weight(.medium))
                    .foregroundStyle(.secondary)
                Text(avail == .unknown && model.orcsBinaryPath == nil
                     ? "Install `orcs` at \(Orcs.expectedPath)."
                     : model.selectedPreset.blurb)
                    .font(ConsoleFont.caption)
                    .foregroundStyle(SurfaceInk.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                Text(avail.caption)
                    .font(ConsoleFont.mono(.caption2))
                    .foregroundStyle(avail.isAvailable ? StatusTone.good.ink : StatusTone.warn.ink)
            }
            .padding(ConsoleMetrics.cardPadding)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .assembling, .running:
            VStack(spacing: 10) {
                ProgressView()
                Text(model.runState == .assembling
                     ? "Assembling prompt from controller evidence…"
                     : "Asking \(model.selectedPreset.commandLabel)…")
                    .font(ConsoleFont.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        default:
            EmptyView()
        }
    }

    private var answerText: some View {
        ScrollView {
            Text(model.streamingOutput)
                .font(ConsoleFont.mono(.callout))
                .foregroundStyle(ConsoleColor.numeral)
                .textSelection(.enabled)
                .lineSpacing(3)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
        }
    }

    // MARK: Prompt inspector

    private func promptInspectorPane(_ prompt: AssembledPrompt) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Button(action: { model.showingPrompt = false }) {
                    Label("Back", systemImage: "chevron.left")
                        .font(ConsoleFont.caption)
                }
                .buttonStyle(.borderless)
                Text("Prompt sent to \(model.selectedPreset.commandLabel)")
                    .font(ConsoleFont.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(prompt.characters) / \(prompt.budget) chars")
                    .font(ConsoleFont.mono(.caption))
                    .foregroundStyle(prompt.overBudget ? StatusTone.bad.ink : Color.secondary)
                if !prompt.trimmed.isEmpty {
                    Text("trimmed: \(prompt.trimmed.joined(separator: ", "))")
                        .font(ConsoleFont.badge)
                        .foregroundStyle(StatusTone.warn.ink)
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)

            Hairline()

            ScrollView {
                Text(prompt.text)
                    .font(ConsoleFont.mono(.caption2))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .lineSpacing(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Preset chip

private struct PresetChip: View {
    let preset: InterpreterPreset
    let availability: PresetAvailability
    let isSelected: Bool
    let action: () -> Void

    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            chipContent
        }
        .buttonStyle(.plain)
        .disabled(!availability.isAvailable)
        .onHover { hovered = $0 }
        .help(preset.blurb + "\n" + availability.detail)
        .accessibilityLabel(preset.title + ". " + availability.caption)
    }

    /// Ceiling on the reason line, so one chip cannot set the width of the whole
    /// bar. `.missingModel` reads "needs Gemma 3 12B — no models installed",
    /// which is wider than the panel's own minimum; the chip's job is to say
    /// *that* it is unavailable, and the sentence explaining why is already in
    /// the tooltip and in the empty state below. The title is left uncapped, so
    /// what truncates is always the annotation and never the name of the thing.
    private static let captionMaxWidth: CGFloat = 168

    private var chipContent: some View {
        VStack(alignment: .leading, spacing: 2) {
            chipHeader
            Text(availability.caption)
                .font(ConsoleFont.badge)
                .foregroundStyle(captionColor)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: Self.captionMaxWidth, alignment: .leading)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .background(chipBackground)
    }

    private var chipHeader: some View {
        HStack(spacing: 4) {
            Image(systemName: preset.symbol)
                .font(ConsoleFont.badge)
            Text(preset.title)
                .font(ConsoleFont.caption.weight(.semibold))
        }
        .foregroundStyle(chipForeground)
    }

    private var chipForeground: AnyShapeStyle {
        if isSelected { return AnyShapeStyle(.tint) }
        if !availability.isAvailable { return AnyShapeStyle(ConsoleColor.dim) }
        return AnyShapeStyle(hovered ? ConsoleColor.numeral : ConsoleColor.indicatorOn)
    }

    private var chipBackground: some View {
        RoundedRectangle(cornerRadius: ConsoleMetrics.rowCorner, style: .continuous)
            .fill(isSelected
                  ? AnyShapeStyle(ConsoleColor.selectionFill)
                  : AnyShapeStyle(hovered ? ConsoleColor.hoverWash : ConsoleColor.surfaceWash))
    }

    /// Rule 3 and rule 8, in one place. "A model is installed" / "the model this
    /// preset needs is missing" / "still checking" is a status, so it comes from
    /// `StatusTone` rather than from a hand-picked `.green` and `.orange` — and
    /// it is a caption, so it takes `ink`. The two literals here were the last
    /// inline hues in the view layer, and they survived because they were bare
    /// `return .green` rather than `Color.green`, which is a shape the audit's
    /// rule-3 pattern did not match.
    private var captionColor: Color {
        switch availability {
        case .available: return StatusTone.good.ink
        case .missingModel: return StatusTone.warn.ink
        case .unknown: return StatusTone.unknown.ink
        }
    }
}
