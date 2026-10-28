import SwiftUI
import FleetCore

struct OurosAgentSheet: View {
    @Bindable var model: AppModel
    @State private var agent: OurosAgent
    @State private var approving: ServiceRecord?
    @Environment(\.dismiss) private var dismiss

    init(model: AppModel) {
        self.model = model
        _agent = State(initialValue: OurosAgent(billing: model.ourosBilling))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Ouros Agent").font(FleetFont.title)
                Spacer()
                Button("Done") { agent.cancel(); dismiss() }.keyboardShortcut(.cancelAction)
            }
            Text("Send the current problems and service records to Ouros for a credit-funded review. Restarts require your approval.")
                .font(FleetFont.caption).foregroundStyle(SurfaceInk.secondary)
            ScrollView {
                Text(agent.answer.isEmpty ? "No review yet." : agent.answer)
                    .textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
            }
            if let message = agent.message { Text(message).font(FleetFont.caption).accessibilityIdentifier("ouros-agent.status") }
            if let key = agent.pendingKey {
                Text("Request " + key).font(FleetFont.caption).textSelection(.enabled)
                Button("Check existing request") { agent.checkPending() }.disabled(agent.busy)
            }
            ForEach(agent.proposedRestarts, id: \.self) { id in
                if let service = model.service(id: id), !service.claimed {
                    Button("Approve restart · \(service.friendlyName)") { approving = service }
                }
            }
            HStack {
                if agent.busy {
                    ProgressView().controlSize(.small)
                    Button("Stop") { agent.cancel() }
                } else {
                    Button("Review problems") {
                        model.loadEvents(serviceID: nil, limit: 40) { events in
                            let services = model.attention.compactMap(\.serviceID).compactMap { model.service(id: $0) }
                            let report = FixReport.markdown(items: model.attention, services: services, events: events,
                                host: Host.current().localizedName ?? "this Mac")
                            agent.start(report: report, services: services)
                        }
                    }.disabled(!model.ourosBilling.signedIn || model.attention.isEmpty || agent.pendingKey != nil)
                        .keyboardShortcut(.defaultAction).accessibilityIdentifier("ouros-agent.review")
                }
                Spacer()
                Text("\(agent.requests.count) requests · confirmed \(agent.chargedUSD.formatted(.currency(code: "USD").precision(.fractionLength(6)))) · \(agent.elapsed, specifier: "%.2f")s")
                    .font(FleetFont.caption).monospacedDigit()
                Button("Usage & credits") { NSWorkspace.shared.open(URL(string: "https://ouros.md/dashboard#/billing")!) }
            }
        }
        .padding(FleetMetrics.gutter).frame(width: 620, height: 440)
        .onDisappear { agent.cancel() }
        .confirmationDialog("Restart \(approving?.friendlyName ?? "service") through FleetConsole?",
            isPresented: Binding(get: { approving != nil }, set: { if !$0 { approving = nil } })) {
                if let service = approving {
                    Button("Restart") {
                        if let current = model.service(id: service.id), !current.claimed { model.restart(current) }
                        approving = nil
                    }
                }
            }
    }
}
