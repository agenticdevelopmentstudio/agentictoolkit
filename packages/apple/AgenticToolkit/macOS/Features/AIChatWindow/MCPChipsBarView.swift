//
//  MCPChipsBarView.swift
//  AgenticToolkit
//
//  Created by Mike Fullerton on 4/30/26.
//

import AppKit
import Combine
import SwiftUI

import AgenticToolkitCore
import AgenticToolkitCoreMacOS

/// Header bar that lets the user pick which configured MCP servers are
/// active for this chat. Hosts a SwiftUI view inside an `NSHostingView`.
///
/// - Note: Not wired to any chat consumer in Phase 1 — the MCP tool loop
///   lives in `MCPChatToolSource`. This bar is retained for Phase 2 when a
///   consumer surfaces the registry selection UI again.
@MainActor
final class MCPChipsBarView: NSView {

    init(registry: MCPServerRegistry, activeServerIds: Binding<Set<UUID>>) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false

        let model = MCPChipsBarViewModel(registry: registry, activeServerIds: activeServerIds)
        let hosting = NSHostingView(rootView: MCPChipsBar(viewModel: model).themedRoot())
        hosting.translatesAutoresizingMaskIntoConstraints = false
        addSubview(hosting)

        NSLayoutConstraint.activate([
            hosting.topAnchor.constraint(equalTo: topAnchor),
            hosting.leadingAnchor.constraint(equalTo: leadingAnchor),
            hosting.trailingAnchor.constraint(equalTo: trailingAnchor),
            hosting.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }
}

@MainActor
private final class MCPChipsBarViewModel: ObservableObject {

    @Published var availableServerIds: [UUID] = []
    @Published var serverNames: [UUID: String] = [:]
    @Published var activeServerIds: Set<UUID>

    private let activeBinding: Binding<Set<UUID>>
    private var cancellables: Set<AnyCancellable> = []

    init(registry: MCPServerRegistry, activeServerIds: Binding<Set<UUID>>) {
        self.activeBinding = activeServerIds
        self.activeServerIds = activeServerIds.wrappedValue

        registry.$clients
            .sink { [weak self] clients in
                guard let self else { return }
                self.availableServerIds = Array(clients.keys).sorted { lhs, rhs in
                    let lhsName = clients[lhs]?.name ?? ""
                    let rhsName = clients[rhs]?.name ?? ""
                    return lhsName.localizedCaseInsensitiveCompare(rhsName) == .orderedAscending
                }
                var names: [UUID: String] = [:]
                for (id, client) in clients {
                    names[id] = client.name
                }
                self.serverNames = names
            }
            .store(in: &cancellables)
    }

    func isActive(_ id: UUID) -> Bool {
        activeServerIds.contains(id)
    }

    func toggle(_ id: UUID) {
        if activeServerIds.contains(id) {
            activeServerIds.remove(id)
        } else {
            activeServerIds.insert(id)
        }
        activeBinding.wrappedValue = activeServerIds
    }
}

private struct MCPChipsBar: View {

    @ObservedObject var viewModel: MCPChipsBarViewModel
    @State private var showingPicker = false

    @Environment(\.theme) private var theme

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "server.rack")
                .foregroundStyle(theme.secondaryText)

            Button {
                showingPicker.toggle()
            } label: {
                HStack(spacing: 4) {
                    Text(buttonLabel)
                    Image(systemName: "chevron.down")
                }
                .font(theme.font(.caption))
                .foregroundStyle(theme.accent)
            }
            .buttonStyle(.borderless)
            .popover(isPresented: $showingPicker, arrowEdge: .bottom) {
                // A popover is its own window, so it is outside this view's
                // environment and needs the palette injected again.
                MCPServerPicker(viewModel: viewModel).themedRoot()
            }

            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    private var buttonLabel: String {
        let active = viewModel.activeServerIds.intersection(Set(viewModel.availableServerIds))
        if viewModel.availableServerIds.isEmpty {
            return "No MCP servers"
        }
        if active.isEmpty {
            return "MCP: none"
        }
        return "MCP: \(active.count) of \(viewModel.availableServerIds.count)"
    }
}

private struct MCPServerPicker: View {

    @ObservedObject var viewModel: MCPChipsBarViewModel

    @Environment(\.theme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Active MCP Servers")
                .font(theme.font(.heading))

            if viewModel.availableServerIds.isEmpty {
                Text("No connected servers.\nAdd one in Settings → MCP Servers.")
                    .foregroundStyle(theme.secondaryText)
                    .font(theme.font(.caption))
            } else {
                ForEach(viewModel.availableServerIds, id: \.self) { id in
                    Toggle(isOn: Binding(
                        get: { viewModel.isActive(id) },
                        set: { _ in viewModel.toggle(id) }
                    )) {
                        Text(viewModel.serverNames[id] ?? "Unknown")
                    }
                    .toggleStyle(.checkbox)
                }
            }
        }
        .padding(14)
        .frame(minWidth: 220)
    }
}
