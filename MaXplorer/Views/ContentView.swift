import AppKit
import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var tabs: BrowserTabsViewModel

    var body: some View {
        VStack(spacing: 0) {
            BrowserTabStrip()

            ActiveBrowserView(model: tabs.activeModel)
                .id(tabs.activeTab.id)
                .environmentObject(tabs.activeModel)
        }
    }
}

private struct ActiveBrowserView: View {
    @EnvironmentObject private var settings: AppSettings
    @ObservedObject var model: FileBrowserViewModel
    @State private var renameItem: FileItem?
    @State private var renameText = ""
    @State private var itemsPendingTrash: [FileItem] = []
    @State private var serverAddress = "smb://"
    @State private var manualFolderPath = ""
    @State private var manualFolderError: String?

    var body: some View {
        NavigationSplitView {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 220, ideal: 260)
        } detail: {
            switch model.detailDestination {
            case .copyQueue:
                CopyQueueView(queue: model.copyQueue)
            case .about:
                AboutView()
            case .settings:
                SettingsSurface()
            case .files:
                VStack(spacing: 0) {
                    BrowserToolbar()
                    FileTableView(
                        renameItem: $renameItem,
                        renameText: $renameText,
                        itemsPendingTrash: $itemsPendingTrash
                    )
                    StatusBar()
                }
                .onKeyPress(.delete) {
                    guard model.canGoBack else {
                        return .ignored
                    }

                    model.goBack()
                    return .handled
                }
            }
        }
        .alert("MaXplorer", isPresented: Binding(
            get: { model.errorMessage != nil },
            set: { if !$0 { model.clearError() } }
        )) {
            Button("OK") {
                model.clearError()
            }
        } message: {
            Text(model.errorMessage ?? "")
        }
        .sheet(item: $renameItem) { item in
            RenameSheet(item: item, renameText: $renameText) {
                Task {
                    await model.renameSelected(to: renameText)
                    renameItem = nil
                }
            } onCancel: {
                renameItem = nil
            }
        }
        .sheet(isPresented: $model.isConnectToServerPresented) {
            ConnectToServerSheet(serverAddress: $serverAddress) {
                model.connectToServer(serverAddress)
            } onCancel: {
                model.isConnectToServerPresented = false
            }
        }
        .sheet(isPresented: $model.isGoToFolderPresented) {
            GoToFolderSheet(
                folderPath: $manualFolderPath,
                history: settings.manualFolderHistory,
                errorMessage: manualFolderError
            ) {
                guard let folderURL = model.navigateToManualFolder(manualFolderPath) else {
                    manualFolderError = model.errorMessage ?? "Path not found"
                    model.clearError()
                    return
                }

                settings.addManualFolderToHistory(folderURL)
                model.isGoToFolderPresented = false
            } onCancel: {
                model.isGoToFolderPresented = false
            }
        }
        .sheet(item: $model.quickViewContent) { content in
            QuickViewSheet(content: content) {
                model.clearQuickView()
            }
        }
        .onChange(of: model.isGoToFolderPresented) { _, isPresented in
            guard isPresented else {
                return
            }

            manualFolderPath = model.currentURL.isFileURL ? model.currentURL.path : ""
            manualFolderError = nil
        }
        .confirmationDialog(
            copyConflictTitle,
            isPresented: Binding(
                get: { model.copyConflictRequest != nil },
                set: { if !$0 { model.copyConflictRequest = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Overwrite", role: .destructive) {
                model.resolveCopyConflict(.overwrite)
            }

            if model.copyConflictRequest?.totalConflicts ?? 0 > 1 {
                Button("Overwrite All", role: .destructive) {
                    model.resolveCopyConflict(.overwriteAll)
                }
            }

            Button("Skip") {
                model.resolveCopyConflict(.skip)
            }

            if model.copyConflictRequest?.totalConflicts ?? 0 > 1 {
                Button("Skip All") {
                    model.resolveCopyConflict(.skipAll)
                }
            }

            Button("Cancel", role: .cancel) {
                model.resolveCopyConflict(.cancel)
            }
        } message: {
            Text(copyConflictMessage)
        }
        .onAppear {
            model.copyQueue.maximumConcurrentCopies = settings.maximumConcurrentCopiedFiles
        }
        .onChange(of: settings.maximumConcurrentCopiedFiles) { _, maximumConcurrentCopiedFiles in
            model.copyQueue.maximumConcurrentCopies = maximumConcurrentCopiedFiles
        }
        .onChange(of: model.renameRequest) { _, item in
            guard let item else {
                return
            }

            renameItem = item
            renameText = item.name
            model.clearRenameRequest()
        }
        .onChange(of: model.trashRequest) { _, items in
            guard !items.isEmpty else {
                return
            }

            itemsPendingTrash = items
            model.clearTrashRequest()
        }
        .confirmationDialog(
            itemsPendingTrash.count == 1 ? "Move item to Trash?" : "Move items to Trash?",
            isPresented: Binding(
                get: { !itemsPendingTrash.isEmpty },
                set: { if !$0 { itemsPendingTrash = [] } }
            )
        ) {
            Button("Move to Trash", role: .destructive) {
                guard !itemsPendingTrash.isEmpty else {
                    return
                }

                let pendingItems = itemsPendingTrash
                Task {
                    await model.moveItemsToTrash(pendingItems)
                    itemsPendingTrash = []
                }
            }

            Button("Cancel", role: .cancel) {
                itemsPendingTrash = []
            }
        } message: {
            if itemsPendingTrash.count == 1, let itemPendingTrash = itemsPendingTrash.first {
                Text(itemPendingTrash.name)
            } else {
                Text("\(itemsPendingTrash.count) selected items")
            }
        }
        .environmentObject(model)
    }

    private var copyConflictTitle: String {
        guard let request = model.copyConflictRequest else { return "" }
        return "\"\(request.conflictingName)\" already exists at the destination"
    }

    private var copyConflictMessage: String {
        guard let request = model.copyConflictRequest else { return "" }
        if request.totalConflicts > 1 {
            return "Conflict \(request.conflictNumber) of \(request.totalConflicts)"
        }
        return "An item with this name already exists. Choose how to handle the conflict."
    }
}

private struct QuickViewSheet: View {
    let content: QuickViewContent
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: "doc.text.magnifyingglass")
                    .font(.system(size: 22, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(Color.accentColor)

                VStack(alignment: .leading, spacing: 3) {
                    Text(content.title)
                        .font(.headline)
                        .lineLimit(1)
                        .truncationMode(.middle)

                    Text(content.detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 16)

                Button("Done", action: onClose)
                    .keyboardShortcut(.defaultAction)
            }
            .padding(16)
            .background(.bar)

            ScrollView {
                Text(content.text)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(.primary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .padding(16)
            }
            .background(Color(nsColor: .textBackgroundColor))
        }
        .frame(minWidth: 680, minHeight: 460)
    }
}

private struct BrowserTabStrip: View {
    @EnvironmentObject private var tabs: BrowserTabsViewModel
    @EnvironmentObject private var settings: AppSettings

    // Chrome-like sizing: tabs share the available width but never grow past a
    // comfortable maximum, and shrink to fit as more tabs open.
    private let maxTabWidth: CGFloat = 190
    private let tabSpacing: CGFloat = 5

    var body: some View {
        GeometryReader { proxy in
            let horizontalPadding: CGFloat = 16
            let addButtonWidth: CGFloat = 30
            let availableWidth = max(
                44,
                proxy.size.width - horizontalPadding - addButtonWidth - tabSpacing * CGFloat(max(tabs.tabs.count - 1, 0))
            )
            let tabWidth = min(maxTabWidth, availableWidth / CGFloat(max(tabs.tabs.count, 1)))

            HStack(spacing: tabSpacing) {
                ForEach(tabs.tabs) { tab in
                    BrowserTabButton(
                        model: tab.model,
                        isSelected: tab.id == tabs.selectedTabID,
                        width: tabWidth,
                        tabID: tab.id,
                        onSelect: { tabs.selectTab(tab.id) },
                        onReorder: { draggedID in tabs.moveTab(draggedID, before: tab.id) },
                        onDropFiles: { urls in
                            tab.model.importItems(urls, maximumConcurrentCopies: settings.maximumConcurrentCopiedFiles)
                        }
                    )
                    .contextMenu {
                        Button("Duplicate Tab") {
                            tabs.duplicateTab(tab.id)
                        }
                        .keyboardShortcut("d", modifiers: [.command, .shift])

                        Divider()

                        Button("Sort by Name") {
                            tabs.sortTabsByName()
                        }

                        Button("Close Duplicate Tabs") {
                            tabs.closeDuplicateTabs()
                        }
                    }
                }

                AddTabButton(isEnabled: tabs.canAddTab) {
                    tabs.addTab()
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .background(.bar)
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(.separator.opacity(0.75))
                    .frame(height: 1)
            }
        }
        .frame(height: 34)
    }
}

private struct AddTabButton: View {
    let isEnabled: Bool
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: "plus")
                .font(.system(size: 12, weight: .semibold))
                .frame(width: 26, height: 24)
                .background(
                    (isHovering && isEnabled) ? Color.primary.opacity(0.08) : .clear,
                    in: RoundedRectangle(cornerRadius: 7)
                )
                .contentShape(RoundedRectangle(cornerRadius: 7))
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .foregroundStyle(isEnabled ? .primary : .tertiary)
        .animation(.easeOut(duration: 0.12), value: isHovering)
        .onHover { isHovering = $0 }
        .modernTooltip(isEnabled ? "Open a new tab (⌘T)" : "Maximum number of tabs reached")
    }
}

private struct BrowserTabButton: View {
    @ObservedObject var model: FileBrowserViewModel
    let isSelected: Bool
    let width: CGFloat
    let tabID: UUID
    let onSelect: () -> Void
    let onReorder: (UUID) -> Void
    let onDropFiles: ([URL]) -> Void

    @State private var isHovering = false
    @State private var isDropTargeted = false
    @State private var springLoadTask: Task<Void, Never>?

    private let cornerRadius: CGFloat = 10

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 6) {
                if width >= 62 {
                    Image(systemName: model.isBrowsingNetwork ? "network" : "folder.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .symbolRenderingMode(.hierarchical)
                }

                Text(model.tabTitle)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, max(7, min(11, width / 12)))
            .frame(width: width, height: 26, alignment: .leading)
            .contentShape(RoundedRectangle(cornerRadius: cornerRadius))
        }
        .buttonStyle(.plain)
        .foregroundStyle(isSelected ? .primary : .secondary)
        .background(tabBackground, in: RoundedRectangle(cornerRadius: cornerRadius))
        .overlay {
            RoundedRectangle(cornerRadius: cornerRadius)
                .stroke(borderStyle, lineWidth: isDropTargeted ? 2 : 1)
        }
        .shadow(color: isSelected ? .black.opacity(0.12) : .clear, radius: 3, y: 1)
        .animation(.easeOut(duration: 0.13), value: isHovering)
        .animation(.easeOut(duration: 0.13), value: isSelected)
        .animation(.easeOut(duration: 0.13), value: isDropTargeted)
        .onHover { isHovering = $0 }
        .draggable(tabID.uuidString)
        .dropDestination(for: String.self) { ids, _ in
            guard let identifier = ids.first, let uuid = UUID(uuidString: identifier) else {
                return false
            }

            onReorder(uuid)
            return true
        }
        .dropDestination(for: URL.self) { urls, _ in
            cancelSpringLoad()
            onDropFiles(urls)
            return true
        } isTargeted: { targeted in
            isDropTargeted = targeted
            if targeted {
                scheduleSpringLoad()
            } else {
                cancelSpringLoad()
            }
        }
        .modernTooltip(model.currentLocationText)
    }

    // Chrome-style spring loading: hovering a dragged file over a tab switches
    // to it after a short delay so items can be dropped into that folder.
    private func scheduleSpringLoad() {
        springLoadTask?.cancel()
        springLoadTask = Task {
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            guard !Task.isCancelled else {
                return
            }

            onSelect()
        }
    }

    private func cancelSpringLoad() {
        springLoadTask?.cancel()
        springLoadTask = nil
    }

    private var borderStyle: AnyShapeStyle {
        if isDropTargeted {
            return AnyShapeStyle(Color.accentColor)
        }

        if isSelected {
            return AnyShapeStyle(Color(nsColor: .separatorColor).opacity(0.7))
        }

        return AnyShapeStyle(Color.clear)
    }

    private var tabBackground: AnyShapeStyle {
        if isSelected {
            return AnyShapeStyle(Color(nsColor: .controlBackgroundColor))
        }

        if isHovering {
            return AnyShapeStyle(Color.primary.opacity(0.09))
        }

        return AnyShapeStyle(Color.clear)
    }
}

private struct SidebarView: View {
    @EnvironmentObject private var model: FileBrowserViewModel
    private let copyQueueSelectionID = "maxplorer://copy-queue"
    private let settingsSelectionID = "maxplorer://settings"
    private let aboutSelectionID = "maxplorer://about"

    var body: some View {
        List(selection: Binding(
            get: {
                switch model.detailDestination {
                case .copyQueue: return copyQueueSelectionID
                case .settings: return settingsSelectionID
                case .about: return aboutSelectionID
                case .files: return model.currentURL.absoluteString
                }
            },
            set: { selection in
                guard let selection else {
                    return
                }

                switch selection {
                case copyQueueSelectionID:
                    model.showCopyQueue()
                case settingsSelectionID:
                    model.showSettings()
                case aboutSelectionID:
                    model.showAbout()
                default:
                    if let url = URL(string: selection) {
                        model.navigate(to: url)
                    }
                }
            }
        )) {
            Section(SidebarLocation.Group.favorites.rawValue) {
                ForEach(model.sidebarLocations.filter { $0.group == .favorites }) { location in
                    Label(location.name, systemImage: location.systemImage)
                        .sidebarHover()
                        .tag(location.url.absoluteString)
                        .contextMenu {
                            if location.canRemoveFromFavorites {
                                Button("Remove from Favorites") {
                                    model.removeFavorite(location.url)
                                }
                            }
                        }
                        .draggable(location.url)
                        .dropDestination(for: URL.self) { urls, _ in
                            _ = handleFavoriteDrop(urls, before: location)
                        }
                }
            }
            .dropDestination(for: URL.self) { urls, _ in
                _ = model.pinDroppedFavorites(urls)
            }

            Section(SidebarLocation.Group.devices.rawValue) {
                ForEach(model.sidebarLocations.filter { $0.group == .devices }) { location in
                    Label(location.name, systemImage: location.systemImage)
                        .sidebarHover()
                        .tag(location.url.absoluteString)
                }
            }

            Section(SidebarLocation.Group.network.rawValue) {
                Button {
                    model.showConnectToServer()
                } label: {
                    Label("Connect to Server", systemImage: "plus.circle")
                }
                .buttonStyle(.plain)

                ForEach(model.sidebarLocations.filter { $0.group == .network }) { location in
                    Label(location.name, systemImage: location.systemImage)
                        .sidebarHover()
                        .tag(location.url.absoluteString)
                }
            }

            Section("Copy Queue") {
                HStack(spacing: 8) {
                    Label("Copy Queue", systemImage: "doc.on.clipboard")

                    Spacer(minLength: 8)

                    if model.copyQueue.activeCopyCount > 0 {
                        PulsingStatusDot()
                    }
                }
                .tag(copyQueueSelectionID)
            }

            Section {
                Divider()
                    .listRowSeparator(.hidden)
                    .padding(.vertical, 2)

                Label("Settings", systemImage: "gearshape")
                    .foregroundStyle(.blue)
                    .sidebarHover()
                    .tag(settingsSelectionID)

                Label("About", systemImage: "info.circle")
                    .foregroundStyle(.blue)
                    .sidebarHover()
                    .tag(aboutSelectionID)
            }
        }
        .listStyle(.sidebar)
        .symbolRenderingMode(.hierarchical)
    }

    private func handleFavoriteDrop(_ urls: [URL], before location: SidebarLocation) -> Bool {
        var didHandle = false

        for url in urls {
            if model.isPinnedFavorite(url) {
                model.moveFavorite(url, before: location.url)
            } else {
                model.pinFavorite(url)
            }

            didHandle = true
        }

        return didHandle
    }
}

private struct PulsingStatusDot: View {
    @State private var isPulsing = false

    var body: some View {
        Circle()
            .fill(Color.blue)
            .frame(width: 8, height: 8)
            .shadow(color: .blue.opacity(0.65), radius: isPulsing ? 5 : 1)
            .opacity(isPulsing ? 0.35 : 1)
            .scaleEffect(isPulsing ? 1.35 : 0.85)
            .animation(
                .easeInOut(duration: 0.75).repeatForever(autoreverses: true),
                value: isPulsing
            )
            .onAppear {
                isPulsing = true
            }
            .accessibilityLabel("Copy in progress")
    }
}

private struct BrowserToolbar: View {
    @EnvironmentObject private var model: FileBrowserViewModel
    @EnvironmentObject private var tabs: BrowserTabsViewModel
    @EnvironmentObject private var settings: AppSettings
    @FocusState private var pathFocused: Bool
    @FocusState private var filterFocused: Bool

    var body: some View {
        VStack(spacing: 8) {
            GlassEffectContainer(spacing: 10) {
            HStack(spacing: 10) {
                ToolbarButtonGroup {
                    ToolbarIconButton(
                        systemName: "chevron.backward",
                        help: "Go back to the previous folder (⌘[)",
                        isDisabled: !model.canGoBack
                    ) {
                        model.goBack()
                    }

                    ToolbarIconButton(
                        systemName: "chevron.forward",
                        help: "Go forward to the next folder (⌘])",
                        isDisabled: !model.canGoForward
                    ) {
                        model.goForward()
                    }

                    ToolbarIconButton(
                        systemName: "arrow.up.to.line.compact",
                        help: "Go to the enclosing folder (⌘↑)",
                        isDisabled: !model.canGoUp
                    ) {
                        model.goUp()
                    }

                    ToolbarIconButton(
                        systemName: "arrow.clockwise",
                        help: "Reload the current folder (⌘R)"
                    ) {
                        model.reload()
                    }
                }

                ToolbarButtonGroup {
                    ToolbarIconButton(
                        systemName: "folder.badge.plus",
                        help: "Create a new folder in the current folder (⌘⇧N)",
                        isDisabled: !model.canCreateFolder
                    ) {
                        Task { await model.createFolder() }
                    }

                    ToolbarIconButton(
                        systemName: "terminal",
                        help: "Open Terminal at the current folder (⌘⇧T)"
                    ) {
                        model.openCurrentFolderInTerminal()
                    }

                    ToolbarIconButton(
                        systemName: "arrow.up.forward.square",
                        help: "Reveal the selected item in Finder (⌃⌘R)"
                    ) {
                        model.revealSelectedInFinder()
                    }
                }

                ToolbarButtonGroup {
                    ToolbarIconButton(
                        systemName: "network.badge.shield.half.filled",
                        help: "Connect to a network server (⌘K)"
                    ) {
                        model.showConnectToServer()
                    }
                }

                ToolbarButtonGroup {
                    ToolbarToggleButton(
                        systemName: "eye.fill",
                        help: tabs.showHiddenFiles ? "Hide hidden files (⌘⇧.)" : "Show hidden files (⌘⇧.)",
                        isOn: $tabs.showHiddenFiles
                    )

                    ToolbarToggleButton(
                        systemName: "a.square.fill",
                        help: tabs.showAliases ? "Hide aliases (⌘⇧A)" : "Show aliases (⌘⇧A)",
                        isOn: $tabs.showAliases,
                        iconSize: 22
                    )
                }

                ToolbarButtonGroup {
                    Menu {
                        Section("Show Columns") {
                            ForEach(FileColumn.allCases) { column in
                                Toggle(column.title, isOn: Binding(
                                    get: { settings.visibleColumns.contains(column) },
                                    set: { _ in settings.toggleColumn(column) }
                                ))
                                .disabled(column.isRequired)
                            }
                        }
                    } label: {
                        Image(systemName: "slider.horizontal.3")
                            .font(.system(size: 14, weight: .semibold))
                            .frame(width: 26, height: 24)
                            .contentShape(Rectangle())
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .fixedSize()
                    .modernTooltip("Choose which columns are shown")
                }

                Spacer(minLength: 12)

                HStack(spacing: 6) {
                    Image(systemName: "line.3.horizontal.decrease.circle")
                        .foregroundStyle(.secondary)
                    TextField("Filter current folder", text: $model.filterText)
                        .textFieldStyle(.plain)
                        .frame(width: 220)
                        .focused($filterFocused)
                }
                .font(.system(size: 13, weight: .medium))
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 10))
                .modernTooltip("Filter items shown in the current folder")
            }
            .symbolRenderingMode(.hierarchical)
            }
            .onChange(of: model.shouldFocusFilter) { _, should in
                guard should else { return }
                filterFocused = true
                model.shouldFocusFilter = false
            }

            HStack(spacing: 8) {
                Image(systemName: "point.topleft.down.curvedto.point.bottomright.up")
                    .foregroundStyle(.secondary)

                TextField("Path", text: $model.pathText)
                    .textFieldStyle(.plain)
                    .focused($pathFocused)
                    .onSubmit {
                        model.submitPath()
                    }

                Button {
                    model.copySelectedPath()
                } label: {
                    Image(systemName: "doc.on.doc")
                }
                .buttonStyle(.borderless)
                .controlSize(.small)
                .modernTooltip("Copy the selected item path, or the current folder path if nothing is selected (⌘⌥C)")
            }
            .symbolRenderingMode(.hierarchical)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 10))
        }
        .padding(12)
        .background(.bar)
        .onExitCommand {
            pathFocused = false
        }
    }
}

private struct CopyQueueView: View {
    @ObservedObject var queue: CopyQueueViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Copy Queue")
                    .font(.headline)

                Spacer()

                Text("\(queue.activeCopyCount) active")
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            .padding(16)
            .background(.bar)

            if queue.items.isEmpty {
                ContentUnavailableView(
                    "No Copy Operations",
                    systemImage: "doc.on.clipboard",
                    description: Text("Copied files will appear here while they are being copied.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(queue.items) { item in
                    CopyQueueRow(item: item) {
                        queue.cancel(item.id)
                    }
                    .listRowInsets(EdgeInsets(top: 10, leading: 14, bottom: 10, trailing: 14))
                }
                .listStyle(.plain)
            }
        }
    }
}

private struct CopyQueueRow: View {
    let item: CopyQueueItem
    let onCancel: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 8) {
                    Text(item.name)
                        .font(.system(size: 13, weight: .medium))
                        .lineLimit(1)
                        .truncationMode(.middle)

                    Text(stateText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                ProgressView(value: item.progress)
                    .progressViewStyle(.linear)

                HStack(spacing: 12) {
                    Text(speedText)
                    Text(etaText)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
            }

            Spacer(minLength: 8)

            Button(action: onCancel) {
                Image(systemName: "xmark")
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!item.state.isActive)
            .foregroundStyle(item.state.isActive ? .secondary : .tertiary)
            .modernTooltip("Cancel this copy operation")
        }
    }

    private var stateText: String {
        switch item.state {
        case .pending:
            return "Pending"
        case .running:
            return "Copying"
        case .completed:
            return "Complete"
        case .failed:
            return "Failed"
        case .cancelled:
            return "Cancelled"
        }
    }

    private var speedText: String {
        guard item.state == .running, item.bytesPerSecond > 0 else {
            return "Speed --"
        }

        return "\(Self.byteFormatter.string(fromByteCount: Int64(item.bytesPerSecond))) /s"
    }

    private var etaText: String {
        guard let estimatedSecondsRemaining = item.estimatedSecondsRemaining else {
            return "ETA --"
        }

        return "ETA \(Self.durationFormatter.string(from: estimatedSecondsRemaining) ?? "--")"
    }

    private static let byteFormatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter
    }()

    private static let durationFormatter: DateComponentsFormatter = {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.hour, .minute, .second]
        formatter.unitsStyle = .abbreviated
        formatter.maximumUnitCount = 2
        return formatter
    }()
}

private struct SettingsSurface: View {
    @EnvironmentObject private var model: FileBrowserViewModel

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                VStack(spacing: 10) {
                    Image(systemName: "gearshape.fill")
                        .font(.system(size: 40, weight: .semibold))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(Color.accentColor)

                    Text("Settings")
                        .font(.system(size: 30, weight: .bold, design: .rounded))

                    Text("Tune appearance, tabs, and copy behavior.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 24)

                SettingsView()
                    .scrollContentBackground(.hidden)
                    .padding(8)
                    .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 22))

                Button {
                    model.dismissAuxiliaryDetail()
                } label: {
                    Text("OK")
                        .font(.headline)
                        .frame(minWidth: 72)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                }
                .buttonStyle(.glassProminent)
                .controlSize(.large)
                .keyboardShortcut(.cancelAction)
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 32)
            .padding(.vertical, 28)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            LinearGradient(
                colors: [Color.accentColor.opacity(0.12), Color.clear],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
        )
    }
}

private struct ToolbarButtonGroup<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        HStack(spacing: 4) {
            content
        }
        .padding(4)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 10))
    }
}

private struct ToolbarIconButton: View {
    let systemName: String
    let help: String
    var isDisabled = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 14, weight: .semibold))
                .frame(width: 26, height: 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(isDisabled ? .tertiary : .primary)
        .disabled(isDisabled)
        .modernTooltip(help)
    }
}

private struct ToolbarToggleButton: View {
    let systemName: String
    let help: String
    @Binding var isOn: Bool
    var iconSize: CGFloat = 14

    var body: some View {
        Button {
            isOn.toggle()
        } label: {
            Image(systemName: systemName)
                .font(.system(size: iconSize, weight: .semibold))
                .frame(width: 26, height: 24)
                .contentShape(Rectangle())
                .background {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(isOn ? Color.accentColor.opacity(0.22) : .clear)
                }
        }
        .buttonStyle(.plain)
        .foregroundStyle(isOn ? Color.accentColor : .primary)
        .modernTooltip(help)
    }
}

private struct ModernTooltipModifier: ViewModifier {
    let text: String
    @Environment(\.colorScheme) private var colorScheme
    @State private var isHovering = false
    @State private var isPresented = false
    @State private var hoverTask: Task<Void, Never>?

    func body(content: Content) -> some View {
        content
            .onHover { hovering in
                isHovering = hovering
                hoverTask?.cancel()

                if hovering {
                    hoverTask = Task {
                        try? await Task.sleep(nanoseconds: 500_000_000)
                        guard !Task.isCancelled else {
                            return
                        }

                        await MainActor.run {
                            if isHovering {
                                isPresented = true
                            }
                        }
                    }
                } else {
                    isPresented = false
                }
            }
            .background(
                TooltipAnchorView(text: text, isPresented: isPresented, colorScheme: colorScheme)
            )
    }
}

private struct TooltipAnchorView: NSViewRepresentable {
    let text: String
    let isPresented: Bool
    let colorScheme: ColorScheme

    func makeNSView(context: Context) -> TooltipAnchorNSView {
        TooltipAnchorNSView()
    }

    func updateNSView(_ nsView: TooltipAnchorNSView, context: Context) {
        nsView.update(text: text, isPresented: isPresented, colorScheme: colorScheme)
    }
}

private final class TooltipAnchorNSView: NSView {
    private var text = ""
    private var isPresented = false
    private var colorScheme: ColorScheme = .light

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updateTooltipVisibility()
    }

    func update(text: String, isPresented: Bool, colorScheme: ColorScheme) {
        self.text = text
        self.isPresented = isPresented
        self.colorScheme = colorScheme
        updateTooltipVisibility()
    }

    private func updateTooltipVisibility() {
        guard isPresented, window != nil else {
            TooltipWindowPresenter.shared.hide(anchor: self)
            return
        }

        TooltipWindowPresenter.shared.show(text: text, anchor: self, colorScheme: colorScheme)
    }
}

@MainActor
private final class TooltipWindowPresenter {
    static let shared = TooltipWindowPresenter()

    private var panel: NSPanel?
    private weak var currentAnchor: NSView?

    func show(text: String, anchor: NSView, colorScheme: ColorScheme) {
        currentAnchor = anchor

        let rootView = TooltipBubble(text: text)
            .environment(\.colorScheme, colorScheme)
        let hostingView = NSHostingView(rootView: rootView)
        hostingView.setFrameSize(hostingView.fittingSize)

        let panel = panel ?? makePanel()
        panel.contentView = hostingView

        let screenFrame = anchor.window?.convertToScreen(anchor.convert(anchor.bounds, to: nil)) ?? .zero
        let panelSize = hostingView.fittingSize
        let origin = NSPoint(
            x: screenFrame.midX - (panelSize.width / 2),
            y: screenFrame.maxY + 8
        )

        panel.setFrame(NSRect(origin: origin, size: panelSize), display: true)
        panel.orderFrontRegardless()
        self.panel = panel
    }

    func hide(anchor: NSView) {
        guard currentAnchor === anchor else {
            return
        }

        panel?.orderOut(nil)
        currentAnchor = nil
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.level = .popUpMenu
        panel.collectionBehavior = [.transient, .ignoresCycle]
        return panel
    }
}

private struct TooltipBubble: View {
    @Environment(\.colorScheme) private var colorScheme
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(foregroundColor)
            .lineLimit(2)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .frame(maxWidth: 280)
            .background(backgroundColor, in: RoundedRectangle(cornerRadius: 8))
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(borderColor, lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.28), radius: 14, y: 7)
    }

    private var backgroundColor: Color {
        colorScheme == .dark ? Color(nsColor: .windowBackgroundColor) : Color(nsColor: .textColor)
    }

    private var foregroundColor: Color {
        colorScheme == .dark ? Color(nsColor: .labelColor) : Color(nsColor: .windowBackgroundColor)
    }

    private var borderColor: Color {
        colorScheme == .dark ? Color(nsColor: .separatorColor) : Color(nsColor: .separatorColor).opacity(0.75)
    }
}

private extension View {
    func modernTooltip(_ text: String) -> some View {
        modifier(ModernTooltipModifier(text: text))
    }

    func sidebarHover() -> some View {
        modifier(SidebarHoverModifier())
    }
}

/// A subtle glass hover highlight for sidebar rows.
private struct SidebarHoverModifier: ViewModifier {
    @State private var isHovering = false

    func body(content: Content) -> some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 3)
            .padding(.horizontal, 6)
            .background {
                if isHovering {
                    RoundedRectangle(cornerRadius: 7)
                        .fill(.thinMaterial)
                        .overlay {
                            RoundedRectangle(cornerRadius: 7)
                                .fill(Color.primary.opacity(0.05))
                        }
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: 7))
            .onHover { isHovering = $0 }
            .animation(.easeOut(duration: 0.12), value: isHovering)
    }
}

private struct FileTableView: View {
    @EnvironmentObject private var model: FileBrowserViewModel
    @EnvironmentObject private var settings: AppSettings
    @Binding var renameItem: FileItem?
    @Binding var renameText: String
    @Binding var itemsPendingTrash: [FileItem]
    @State private var isDropTargeted = false
    @State private var folderDropTargetID: FileItem.ID?

    private var columns: Set<FileColumn> { settings.visibleColumns }

    var body: some View {
        ZStack {
            Table(model.displayedItems, selection: Binding(
                get: { model.selectedItemIDs },
                set: { model.selectedItemIDs = $0 }
            ), sortOrder: $model.sortOrder) {
                TableColumn("Name", value: \.name) { item in
                    nameCell(for: item)
                }
                .width(min: 220, ideal: 320)

                if columns.contains(.kind) {
                    TableColumn("Kind", value: \.displayKind) { item in
                        columnText(item.displayKind, for: item)
                    }
                    .width(min: 120, ideal: 170)
                }

                if columns.contains(.size) {
                    TableColumn("Size", value: \.sortSize) { item in
                        columnText(item.displaySize, for: item, monospacedDigit: true)
                    }
                    .width(min: 80, ideal: 110)
                }

                if columns.contains(.dateModified) {
                    TableColumn("Date Modified", value: \.sortModifiedAt) { item in
                        columnText(item.displayModified, for: item)
                    }
                    .width(min: 150, ideal: 180)
                }

                if columns.contains(.dateCreated) {
                    TableColumn("Date Created", value: \.sortCreatedAt) { item in
                        columnText(item.displayCreated, for: item)
                    }
                    .width(min: 150, ideal: 180)
                }

                if columns.contains(.dateTaken) {
                    TableColumn("Date Taken", value: \.sortDateTaken) { item in
                        columnText(item.displayDateTaken, for: item)
                    }
                    .width(min: 150, ideal: 180)
                }

                if columns.contains(.owner) {
                    TableColumn("Owner", value: \.sortOwner) { item in
                        columnText(item.displayOwner, for: item)
                    }
                    .width(min: 100, ideal: 140)
                }
            }
            .dropDestination(for: URL.self) { urls, _ in
                model.importItems(urls, maximumConcurrentCopies: settings.maximumConcurrentCopiedFiles)
                return true
            } isTargeted: { isDropTargeted = $0 }
            .overlay {
                if isDropTargeted {
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 2, dash: [6]))
                        .padding(2)
                        .allowsHitTesting(false)
                }
            }
            .contextMenu(forSelectionType: FileItem.ID.self) { selection in
                Button("Open") {
                    model.selectedItemIDs = selection
                    model.openSelected()
                }

                Button("Quick View") {
                    model.selectedItemIDs = selection
                    model.quickViewSelectedItem()
                }
                .disabled(!canQuickView(selection: selection))

                Menu("Open With") {
                    let applications = openWithApplications(selection: selection)
                    if applications.isEmpty {
                        Text("No Applications Found")
                    } else {
                        ForEach(applications) { application in
                            Button(application.name) {
                                model.selectedItemIDs = selection
                                model.openSelected(with: application)
                            }
                        }
                    }
                }
                .disabled(!canOpenWith(selection: selection))

                Divider()

                Button("Cut") {
                    model.selectedItemIDs = selection
                    model.cutSelectedItems()
                }
                .disabled(!canCut(selection: selection))

                Button("Copy") {
                    model.selectedItemIDs = selection
                    model.copySelectedItems()
                }
                .disabled(!canCut(selection: selection))

                Button("Rename") {
                    startRename(selection: selection)
                }
                .disabled(!canEdit(selection: selection))

                Button("Move to Trash", role: .destructive) {
                    startTrash(selection: selection)
                }
                .disabled(!canTrash(selection: selection))

                Divider()

                Button("Add to Favorites") {
                    pinFolder(selection: selection)
                }
                .disabled(!canPin(selection: selection))

                Divider()

                Button("Copy Path") {
                    model.selectedItemIDs = selection
                    model.copySelectedPath()
                }

                Button("Open in Terminal") {
                    model.selectedItemIDs = selection
                    model.openSelectedInTerminal()
                }

                Button("Reveal in Finder") {
                    model.selectedItemIDs = selection
                    model.revealSelectedInFinder()
                }
            } primaryAction: { selection in
                model.selectedItemIDs = selection
                model.openSelected()
            }

            if model.isLoading {
                ProgressView()
                    .controlSize(.large)
                    .padding(22)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
            } else if model.displayedItems.isEmpty {
                ContentUnavailableView(
                    model.filterText.isEmpty ? "No Items" : "No Matching Items",
                    systemImage: model.filterText.isEmpty ? (model.isBrowsingNetwork ? "network.slash" : "folder") : "magnifyingglass",
                    description: Text(emptyDescription)
                )
            }
        }
    }

    private func startRename(selection: Set<FileItem.ID>) {
        guard let id = selection.first, let item = model.items.first(where: { $0.id == id }) else {
            return
        }

        model.selectedItemIDs = [id]
        renameItem = item
        renameText = item.name
    }

    private func startTrash(selection: Set<FileItem.ID>) {
        let items = model.items.filter { selection.contains($0.id) && !$0.isNetworkLocation }
        guard !items.isEmpty else {
            return
        }

        model.selectedItemIDs = Set(items.map(\.id))
        itemsPendingTrash = items
    }

    private func pinFolder(selection: Set<FileItem.ID>) {
        guard let id = selection.first else {
            return
        }

        model.selectedItemIDs = [id]
        model.pinSelectedFolderToFavorites()
    }

    private func selectedItem(for selection: Set<FileItem.ID>) -> FileItem? {
        guard selection.count == 1, let id = selection.first else {
            return nil
        }

        return model.items.first { $0.id == id }
    }

    private func canPin(selection: Set<FileItem.ID>) -> Bool {
        guard let item = selectedItem(for: selection) else {
            return false
        }

        return model.canPinFolder(item)
    }

    private func canQuickView(selection: Set<FileItem.ID>) -> Bool {
        guard let item = selectedItem(for: selection) else {
            return false
        }

        return model.canQuickView(item)
    }

    private func canOpenWith(selection: Set<FileItem.ID>) -> Bool {
        guard let item = selectedItem(for: selection) else {
            return false
        }

        return model.canOpenWith(item)
    }

    private func openWithApplications(selection: Set<FileItem.ID>) -> [OpenWithApplication] {
        guard let item = selectedItem(for: selection) else {
            return []
        }

        return model.openWithApplications(for: item)
    }

    private func canCut(selection: Set<FileItem.ID>) -> Bool {
        selection.contains { id in
            model.items.first { $0.id == id }?.isNetworkLocation == false
        }
    }

    private func canEdit(selection: Set<FileItem.ID>) -> Bool {
        guard selection.count == 1, let id = selection.first, let item = model.items.first(where: { $0.id == id }) else {
            return false
        }

        return !item.isNetworkLocation
    }

    private func canTrash(selection: Set<FileItem.ID>) -> Bool {
        selection.contains { id in
            model.items.first { $0.id == id }?.isNetworkLocation == false
        }
    }

    private var emptyDescription: String {
        if !model.filterText.isEmpty {
            return "The current-folder filter did not match loaded items."
        }

        if model.isBrowsingNetwork {
            return "No local SMB servers or mounted network volumes were found. Use Connect to Server for a known address."
        }

        return "This folder is empty or unavailable."
    }

    @ViewBuilder
    private func nameCell(for item: FileItem) -> some View {
        let isFolderTarget = folderDropTargetID == item.id
        HStack(spacing: 8) {
            FileItemIcon(item: item)
            Text(item.name).lineLimit(1)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .opacity(model.isCut(item) ? 0.45 : 1)
        .background(
            isFolderTarget ? Color.accentColor.opacity(0.18) : Color.clear,
            in: RoundedRectangle(cornerRadius: 4)
        )
        .overlay { rowClickTarget(for: item) }
        .draggable(item.url)
        .dropDestination(for: URL.self) { urls, _ in
            guard let dest = item.navigationURL else { return false }
            model.moveItems(urlsExpandingSelection(urls), to: dest)
            return true
        } isTargeted: { targeted in
            folderDropTargetID = (targeted && item.navigationURL != nil) ? item.id : nil
        }
    }

    /// If the dragged URL is one of the currently selected items, return all
    /// selected URLs so a multi-selection drag moves everything at once.
    private func urlsExpandingSelection(_ droppedURLs: [URL]) -> [URL] {
        let droppedStd = Set(droppedURLs.map(\.standardizedFileURL))
        let selectedURLs = model.displayedItems
            .filter { model.selectedItemIDs.contains($0.id) }
            .map(\.url)
        let selectedStd = Set(selectedURLs.map(\.standardizedFileURL))
        return droppedStd.isDisjoint(with: selectedStd) ? droppedURLs : selectedURLs
    }

    private func rowClickTarget(for item: FileItem) -> some View {
        TableCellClickTarget { mode in
            model.select(item, mode: mode)
        } onOpen: {
            model.selectedItemIDs = [item.id]
            model.openSelected()
        }
    }

    @ViewBuilder
    private func columnText(_ text: String, for item: FileItem, monospacedDigit: Bool = false) -> some View {
        Text(text)
            .foregroundStyle(.secondary)
            .font(monospacedDigit ? .body.monospacedDigit() : .body)
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay { rowClickTarget(for: item) }
    }
}

private struct StatusBar: View {
    @EnvironmentObject private var model: FileBrowserViewModel

    var body: some View {
        HStack(spacing: 10) {
            if model.isLoading {
                ProgressView()
                    .controlSize(.small)
                Text("Loading")
            } else {
                Text("\(model.displayedItems.count) of \(model.items.count) items")
            }

            Spacer()

            Text(model.currentLocationText)
                .lineLimit(1)
                .truncationMode(.middle)
                .foregroundStyle(.secondary)
        }
        .font(.footnote)
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(.bar)
    }
}

private struct TableCellClickTarget: NSViewRepresentable {
    let onSelect: (SelectionMode) -> Void
    let onOpen: () -> Void

    func makeNSView(context: Context) -> TableCellClickTargetNSView {
        let view = TableCellClickTargetNSView()
        view.onSelect = onSelect
        view.onOpen = onOpen
        return view
    }

    func updateNSView(_ nsView: TableCellClickTargetNSView, context: Context) {
        nsView.onSelect = onSelect
        nsView.onOpen = onOpen
    }
}

private final class TableCellClickTargetNSView: NSView {
    var onSelect: (SelectionMode) -> Void = { _ in }
    var onOpen: () -> Void = {}

    override var acceptsFirstResponder: Bool { true }

    override func mouseDown(with event: NSEvent) {
        if event.modifierFlags.contains(.shift) {
            onSelect(.range)
        } else if event.modifierFlags.contains(.command) {
            onSelect(.toggle)
        } else {
            onSelect(.single)
        }

        if event.clickCount >= 2 {
            onOpen()
        }
    }
}

private struct FileItemIcon: View {
    let item: FileItem

    var body: some View {
        Group {
            if item.isNetworkLocation {
                Image(systemName: "server.rack")
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.mint)
            } else if item.isAlias && item.opensInApp {
                FolderAliasIcon()
            } else if item.opensInApp {
                Image(systemName: "folder.fill")
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.blue)
            } else if item.isPackage {
                Image(systemName: "shippingbox.fill")
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.orange)
            } else {
                Image(systemName: "doc.richtext.fill")
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.secondary)
            }
        }
        .font(.system(size: 17, weight: .semibold))
        .frame(width: 22, height: 18)
    }
}

private struct FolderAliasIcon: View {
    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Image(systemName: "folder.fill")
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.blue)

            Text("A")
                .font(.system(size: 8, weight: .black, design: .rounded))
                .foregroundStyle(.white)
                .frame(width: 12, height: 12)
                .background(.indigo, in: Circle())
                .overlay {
                    Circle()
                        .stroke(.background, lineWidth: 1.3)
                }
                .offset(x: 4, y: 3)
        }
    }
}

private struct RenameSheet: View {
    let item: FileItem
    @Binding var renameText: String
    let onSave: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Rename")
                .font(.headline)

            TextField("Name", text: $renameText)
                .textFieldStyle(.roundedBorder)
                .frame(width: 360)
                .onSubmit(onSave)

            Text(item.url.deletingLastPathComponent().path)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)

            HStack {
                Spacer()
                Button("Cancel", action: onCancel)
                Button("Rename", action: onSave)
                    .buttonStyle(.borderedProminent)
                    .disabled(renameText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(20)
    }
}

private struct ConnectToServerSheet: View {
    @Binding var serverAddress: String
    let onConnect: () -> Void
    let onCancel: () -> Void

    private var trimmedAddress: String {
        serverAddress.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Connect to Server")
                .font(.headline)

            TextField("smb://server/share", text: $serverAddress)
                .textFieldStyle(.roundedBorder)
                .frame(width: 390)
                .onSubmit(onConnect)

            HStack {
                Spacer()
                Button("Cancel", action: onCancel)
                Button("Connect", action: onConnect)
                    .buttonStyle(.borderedProminent)
                    .disabled(trimmedAddress.isEmpty || trimmedAddress == "smb://")
            }
        }
        .padding(20)
    }
}

private struct GoToFolderSheet: View {
    @Binding var folderPath: String
    let history: [String]
    let errorMessage: String?
    let onGo: () -> Void
    let onCancel: () -> Void

    private var trimmedPath: String {
        folderPath.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Go to Folder")
                .font(.headline)

            ManualFolderComboBox(text: $folderPath, history: history, onCommit: onGo)
                .frame(width: 420, height: 26)

            if let errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }

            HStack {
                Spacer()
                Button("Cancel", action: onCancel)
                Button("Go", action: onGo)
                    .buttonStyle(.borderedProminent)
                    .disabled(trimmedPath.isEmpty)
            }
        }
        .padding(20)
    }
}

private struct ManualFolderComboBox: NSViewRepresentable {
    @Binding var text: String
    let history: [String]
    let onCommit: () -> Void

    func makeNSView(context: Context) -> NSComboBox {
        let comboBox = NSComboBox()
        comboBox.usesDataSource = false
        comboBox.completes = false
        comboBox.numberOfVisibleItems = 8
        comboBox.delegate = context.coordinator
        return comboBox
    }

    func updateNSView(_ nsView: NSComboBox, context: Context) {
        context.coordinator.text = $text
        context.coordinator.onCommit = onCommit

        if nsView.objectValue as? String != text {
            nsView.objectValue = text
        }

        nsView.removeAllItems()
        nsView.addItems(withObjectValues: history)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, onCommit: onCommit)
    }

    @MainActor
    final class Coordinator: NSObject, NSComboBoxDelegate {
        var text: Binding<String>
        var onCommit: () -> Void

        init(text: Binding<String>, onCommit: @escaping () -> Void) {
            self.text = text
            self.onCommit = onCommit
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let comboBox = notification.object as? NSComboBox else {
                return
            }

            text.wrappedValue = comboBox.stringValue
        }

        func comboBoxSelectionDidChange(_ notification: Notification) {
            guard let comboBox = notification.object as? NSComboBox else {
                return
            }

            text.wrappedValue = comboBox.stringValue
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            guard commandSelector == #selector(NSResponder.insertNewline(_:)) else {
                return false
            }

            text.wrappedValue = control.stringValue
            onCommit()
            return true
        }
    }
}

