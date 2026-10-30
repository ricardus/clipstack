import AppKit
import SwiftUI

@MainActor
struct HistoryView: View {
    @ObservedObject var state: AppState
    let onActivate: (ClipItem) -> Void

    @FocusState private var searchFocused: Bool

    private var store: ClipStore { state.store }

    var body: some View {
        VStack(spacing: 0) {
            searchBar
            Divider()
            filterBar
            Divider()
            list
        }
        .frame(minWidth: 480, minHeight: 420)
        .onAppear { searchFocused = true }
    }

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Search history", text: $state.query)
                .textFieldStyle(.plain)
                .font(.system(size: 14))
                .focused($searchFocused)
                .onChange(of: state.query) { _, _ in state.resetSelection() }
            if !state.query.isEmpty {
                Button {
                    state.query = ""
                    state.resetSelection()
                } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    private var filterBar: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    chip(title: "All", isActive: state.isUnfiltered) {
                        state.clearFilters()
                    }
                    chip(title: "Pin", symbol: "pin.fill", isActive: state.pinnedOnly) {
                        state.pinnedOnly.toggle()
                        state.resetSelection()
                    }
                    ForEach(ClipKind.allCases) { kind in
                        chip(title: kind.label,
                             symbol: kind.symbol,
                             isActive: state.kindFilter == kind) {
                            state.kindFilter = state.kindFilter == kind ? nil : kind
                            state.resetSelection()
                        }
                        .id(kind)
                    }

                    if !state.knownApps.isEmpty {
                        Divider().frame(height: 16)
                        Menu {
                            Button("Any app") {
                                state.appFilter = nil
                                state.resetSelection()
                            }
                            ForEach(state.knownApps) { app in
                                Button(app.name) {
                                    state.appFilter = app.id
                                    state.resetSelection()
                                }
                            }
                        } label: {
                            Label(currentAppFilterName, systemImage: "app.badge")
                                .font(.system(size: 11))
                        }
                        .menuStyle(.borderlessButton)
                        .fixedSize()
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
            // Keeps the chip picked with the arrow keys in view on narrow panels.
            .onChange(of: state.kindFilter) { _, kind in
                guard let kind else { return }
                withAnimation(.easeOut(duration: 0.12)) { proxy.scrollTo(kind, anchor: .center) }
            }
        }
    }

    private var currentAppFilterName: String {
        guard let appFilter = state.appFilter else { return "Any app" }
        return state.knownApps.first { $0.id == appFilter }?.name ?? appFilter
    }

    private var list: some View {
        ScrollViewReader { proxy in
            ScrollView {
                let items = state.visible
                let pinnedCount = items.prefix(while: { $0.pinned }).count
                let sectioned = !state.pinnedOnly && pinnedCount > 0 && pinnedCount < items.count
                LazyVStack(spacing: 2) {
                    if items.isEmpty {
                        emptyState
                    }
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                        if sectioned, index == 0 {
                            sectionHeader("Pinned", count: pinnedCount)
                        } else if sectioned, index == pinnedCount {
                            sectionHeader("Recent", count: nil)
                        }
                        ClipRowView(item: item,
                                    isSelected: index == state.selectionIndex,
                                    tinted: sectioned && item.pinned,
                                    store: store)
                            .id(item.id)
                            .onTapGesture { onActivate(item) }
                            .onDrag { dragProvider(for: item) }
                            .contextMenu {
                                Button(item.pinned ? "Unpin" : "Pin") { store.togglePin(item) }
                                Button("Copy without pasting") {
                                    Paster.copyToPasteboard(item, store: store)
                                }
                                Divider()
                                Button("Delete", role: .destructive) { store.delete(item) }
                            }
                    }
                }
                .padding(8)
            }
            .onChange(of: state.selectionIndex) { _, _ in
                guard let id = state.selectedItem?.id else { return }
                withAnimation(.easeOut(duration: 0.12)) { proxy.scrollTo(id, anchor: .center) }
            }
        }
    }

    private func sectionHeader(_ title: String, count: Int?) -> some View {
        HStack(spacing: 7) {
            Text(title.uppercased())
                .font(.system(size: 9.5, weight: .semibold))
                .tracking(0.9)
                .foregroundStyle(.tertiary)
            if let count {
                Text("\(count)")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(RoundedRectangle(cornerRadius: 4).fill(Color.primary.opacity(0.07)))
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 4)
        .padding(.top, 7)
        .padding(.bottom, 2)
    }

    private var emptyState: some View {
        VStack(spacing: 6) {
            Image(systemName: "clipboard")
                .font(.system(size: 28))
                .foregroundStyle(.tertiary)
            Text(emptyStateMessage)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }

    private var emptyStateMessage: String {
        if state.pinnedOnly && state.query.isEmpty { return "Nothing pinned yet" }
        if !state.query.isEmpty { return "No matches" }
        return "Nothing captured yet"
    }

    /// Images drag out as the real file on disk; everything else as text.
    private func dragProvider(for item: ClipItem) -> NSItemProvider {
        if item.kind == .image, let url = store.blobURL(for: item),
           let provider = NSItemProvider(contentsOf: url) {
            return provider
        }
        return NSItemProvider(object: (item.text ?? item.preview) as NSString)
    }
}

@MainActor
extension HistoryView {
    @ViewBuilder
    func chip(title: String,
              symbol: String? = nil,
              isActive: Bool,
              action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if let symbol { Image(systemName: symbol).font(.system(size: 10)) }
                Text(title).font(.system(size: 11, weight: isActive ? .semibold : .regular))
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(
                Capsule().fill(isActive ? Theme.accent.opacity(0.9) : Color.primary.opacity(0.07))
            )
            .foregroundStyle(isActive ? Color.white : Color.primary)
        }
        .buttonStyle(.plain)
    }
}
