import AppKit

extension ComposableSettings {

    /// Sidebar list of settings panels. Subclass of `TopicListViewController` that
    /// maps `[SettingsPanelViewController]` to `TopicListSection`s and translates
    /// row selection back to the owning panel. Open so client apps can customize
    /// row presentation or add secondary actions.
    @MainActor
    open class PanelListViewController: TopicListViewController {

        /// Fired when the user picks a row. Nil when nothing is selected.
        public var onSelectPanel: (((any ComposableSettingsPanel)?) -> Void)?

        /// Narrows the visible rows to the panels matching this text. Empty shows
        /// every panel, so clearing the search field restores the full list.
        ///
        /// Filtering the sidebar (rather than replacing it with a results list) is
        /// what keeps a search reversible: the row the user is reading stays where
        /// it was in the list, and deleting the query puts its neighbours back
        /// around it.
        public var searchQuery: String = "" {
            didSet {
                guard oldValue != searchQuery else { return }
                rebuildSections()
            }
        }

        private var panels: [any ComposableSettingsPanel] = []
        private let searchIndex = SettingsSearchIndex()

        public override init(nibName: NSNib.Name?, bundle: Bundle?) {
            super.init(nibName: nibName, bundle: bundle)
            // onSelect is a superclass implementation hook owned by this subclass;
            // external consumers should use `onSelectPanel`.
            onSelect = { [weak self] item in
                guard let self else { return }
                self.onSelectPanel?(item.flatMap { self.panel(forId: $0.id) })
            }
        }

        public required init?(coder: NSCoder) { super.init(coder: coder) }

        public func setPanels(_ panels: [any ComposableSettingsPanel]) {
            self.panels = panels
            rebuildSections()
        }

        /// Selects the row at `index` without firing `onSelectPanel`, since
        /// programmatic selection flows through `SettingsViewController.selectPanel`.
        public func selectPanel(at index: Int) {
            guard panels.indices.contains(index) else { return }
            selectItem(withId: String(index))
        }

        /// Whether the current query admits the panel at `index` — that is,
        /// whether `selectPanel(at:)` has a row to land on at all.
        ///
        /// `selectItem(withId:)` is a silent no-op for a row the filter has
        /// hidden, so a caller that must end up with a highlight has to know
        /// beforehand whether it will get one. Asked rather than assumed,
        /// because clearing the search on the caller's behalf when it was not
        /// needed throws away a filter the user is still reading by.
        public func isPanelVisible(at index: Int) -> Bool {
            visiblePanels().contains { $0.index == index }
        }

        // MARK: - Internals

        private func rebuildSections() {
            setSections(Self.buildSections(from: visiblePanels()))
        }

        /// The panels the current query admits, each paired with its position in
        /// the full list. The position is the row's identity, so a filtered row
        /// still selects the panel it names.
        private func visiblePanels() -> [(index: Int, panel: any ComposableSettingsPanel)] {
            panels.enumerated()
                .filter { searchIndex.matches($0.element, query: searchQuery) }
                .map { (index: $0.offset, panel: $0.element) }
        }

        private func panel(forId id: String) -> (any ComposableSettingsPanel)? {
            guard let index = Int(id), panels.indices.contains(index) else { return nil }
            return panels[index]
        }

        private static func buildSections(
            from panels: [(index: Int, panel: any ComposableSettingsPanel)]
        ) -> [TopicListSection] {
            // Sections come out in the order the panels arrive, and a run of
            // panels sharing one section title is one section. Grouping by title
            // across the whole list instead hoisted every unsectioned panel to
            // the top of the sidebar, silently reordering a list whose author had
            // already put it in the order they meant.
            var runs: [(title: String?, items: [TopicListItem])] = []
            for entry in panels {
                let item = TopicListItem(
                    id: String(entry.index),
                    title: entry.panel.descriptor.title,
                    icon: entry.panel.descriptor.icon,
                    isDisabled: entry.panel.descriptor.isDisabled
                )
                if !runs.isEmpty, runs[runs.count - 1].title == entry.panel.descriptor.section {
                    runs[runs.count - 1].items.append(item)
                } else {
                    runs.append((title: entry.panel.descriptor.section, items: [item]))
                }
            }
            return runs.map { TopicListSection(title: $0.title, items: $0.items) }
        }
    }
}
