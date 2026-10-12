import SwiftUI
import FleetCore

// Module: Events — the append-only log, filterable.
//
// The registry's event table rejects UPDATE and DELETE; this view honours that
// by being a pure projection. Timestamps are HH:mm:ss in mono digits because
// this is where ordering disputes get settled, and bad events carry their
// tone through shape (octagon/triangle) as well as colour.

struct EventsModule: View {
    @Bindable var model: AppModel
    @Bindable var console: ConsoleModel

    @State private var events: [ServiceEvent] = []
    @State private var loadedMore = false

    private var query: String { console.search.trimmingCharacters(in: .whitespaces) }

    private var shown: [ServiceEvent] {
        let source = loadedMore ? events : model.recentEvents
        guard !query.isEmpty else { return source }
        return source.filter {
            $0.kind.label.localizedCaseInsensitiveContains(query)
                || $0.detail.localizedCaseInsensitiveContains(query)
                || ($0.serviceName?.localizedCaseInsensitiveContains(query) ?? false)
        }
    }

    var body: some View {
        List {
            Section {
                if shown.isEmpty {
                    Text(query.isEmpty ? "No events recorded yet." : "No events match “\(query)”.")
                        .font(ConsoleFont.caption)
                        .foregroundStyle(SurfaceInk.secondary)
                } else {
                    ForEach(shown) { event in
                        EventRow(event: event)
                    }
                }
            } header: {
                HStack {
                    Text("Append-only · newest first")
                        .font(ConsoleFont.caption)
                        .foregroundStyle(SurfaceInk.secondary)
                        .textCase(nil)
                    Spacer()
                    if !loadedMore {
                        Button("Load 300") { load() }
                            .buttonStyle(.link)
                            .font(ConsoleFont.caption)
                    }
                }
            }
        }
        .listStyle(.inset)
        // The table sits on the page like every other surface: without
        // this it paints AppKit's own table background over the field and
        // the module reads as a panel dropped on top of the window rather
        // than as part of it.
        .scrollContentBackground(.hidden)
    }

    private func load() {
        model.loadEvents(serviceID: nil, limit: 300) { loaded in
            events = loaded
            loadedMore = true
        }
    }
}

private struct EventRow: View {
    let event: ServiceEvent

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: event.kind.isBad
                  ? (event.kind == .crashed ? "xmark.octagon.fill" : "exclamationmark.triangle.fill")
                  : "circle.fill")
                .font(.system(size: event.kind.isBad ? 11 : 6))
                .foregroundStyle(event.kind.isBad ? StatusTone.bad.ink : ConsoleColor.dim)
                .frame(width: 14, alignment: .center)
                .padding(.top, event.kind.isBad ? 1 : 5)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(event.kind.label)
                        .font(ConsoleFont.rowTitle.weight(.medium))
                    if let name = event.serviceName {
                        Text(name)
                            .font(ConsoleFont.caption)
                            .foregroundStyle(.tint)
                            .lineLimit(1)
                    }
                }
                if !event.detail.isEmpty {
                    Text(event.detail)
                        .font(ConsoleFont.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 8)
            Text(ConsoleFmt.timestamp(event.ts))
                .font(ConsoleFont.mono(.caption))
                .monospacedDigit()
                .foregroundStyle(SurfaceInk.secondary)
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
        .hoverHighlight()
        .contextMenu {
            Text(event.kind.label)
            Divider()
            Button("Copy Event Detail") {
                let text = event.detail.isEmpty
                    ? "\(ConsoleFmt.timestamp(event.ts)) \(event.kind.label)"
                    : "\(ConsoleFmt.timestamp(event.ts)) \(event.kind.label) — \(event.detail)"
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(text, forType: .string)
            }
            if let name = event.serviceName {
                Button("Copy Service Name") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(name, forType: .string)
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(event.kind.label)\(event.detail.isEmpty ? "" : ": \(event.detail)")")
    }
}
