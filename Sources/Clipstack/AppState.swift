import AppKit
import Combine
import Foundation

/// View state for the history panel: search text, active filters and keyboard
/// selection. Kept separate from ClipStore so filtering never touches storage.
struct AppSource: Identifiable, Hashable {
    let id: String
    let name: String
}

@MainActor
final class AppState: ObservableObject {
    @Published var query = ""
    @Published var kindFilter: ClipKind?
    @Published var appFilter: String?
    /// Narrows the list to pinned entries. Orthogonal to `kindFilter`, so
    /// "pinned images" is a valid combination.
    @Published var pinnedOnly = false
    @Published var selectionIndex = 0

    let store: ClipStore
    private var cancellables: Set<AnyCancellable> = []

    init(store: ClipStore) {
        self.store = store
        store.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
    }

    var visible: [ClipItem] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return store.items.filter { item in
            if pinnedOnly, !item.pinned { return false }
            if let kindFilter, item.kind != kindFilter { return false }
            if let appFilter, item.appBundleID != appFilter { return false }
            if !needle.isEmpty, !item.searchHaystack.contains(needle) { return false }
            return true
        }
    }

    /// Apps present in the current history, for the source filter menu.
    var knownApps: [AppSource] {
        var seen: [String: String] = [:]
        for item in store.items {
            guard let bundleID = item.appBundleID else { continue }
            if seen[bundleID] == nil { seen[bundleID] = item.appName ?? bundleID }
        }
        return seen.map { AppSource(id: $0.key, name: $0.value) }.sorted { $0.name < $1.name }
    }

    var selectedItem: ClipItem? {
        let items = visible
        guard items.indices.contains(selectionIndex) else { return nil }
        return items[selectionIndex]
    }

    func moveSelection(by offset: Int) {
        let count = visible.count
        guard count > 0 else { selectionIndex = 0; return }
        selectionIndex = min(max(selectionIndex + offset, 0), count - 1)
    }

    /// Steps the type filter through All and each kind, wrapping at both ends.
    /// Leaves the pin and app filters alone.
    func cycleKindFilter(by offset: Int) {
        let options: [ClipKind?] = [nil] + ClipKind.allCases
        let current = options.firstIndex(of: kindFilter) ?? 0
        kindFilter = options[(current + offset % options.count + options.count) % options.count]
        selectionIndex = 0
    }

    func resetSelection() {
        selectionIndex = 0
    }

    func reset() {
        query = ""
        kindFilter = nil
        appFilter = nil
        pinnedOnly = false
        selectionIndex = 0
    }

    /// True when no filter is narrowing the list.
    var isUnfiltered: Bool {
        kindFilter == nil && appFilter == nil && !pinnedOnly
    }

    func clearFilters() {
        kindFilter = nil
        appFilter = nil
        pinnedOnly = false
        selectionIndex = 0
    }
}
