import AppKit
import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var model: FileBrowserViewModel
    @State private var renameItem: FileItem?
    @State private var renameText = ""
    @State private var itemPendingTrash: FileItem?
    @State private var serverAddress = "smb://"

    var body: some View {
        NavigationSplitView {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 220, ideal: 260)
        } detail: {
            VStack(spacing: 0) {
                BrowserToolbar()
                FileTableView(
                    renameItem: $renameItem,
                    renameText: $renameText,
                    itemPendingTrash: $itemPendingTrash
                )
                StatusBar()
            }
        }
        .alert("MacXplorer", isPresented: Binding(
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
        .onChange(of: model.renameRequest) { _, item in
            guard let item else {
                return
            }

            renameItem = item
            renameText = item.name
            model.clearRenameRequest()
        }
        .onChange(of: model.trashRequest) { _, item in
            guard let item else {
                return
            }

            itemPendingTrash = item
            model.clearTrashRequest()
        }
        .confirmationDialog(
            "Move item to Trash?",
            isPresented: Binding(
                get: { itemPendingTrash != nil },
                set: { if !$0 { itemPendingTrash = nil } }
            )
        ) {
            Button("Move to Trash", role: .destructive) {
                guard let pendingItem = itemPendingTrash else {
                    return
                }

                Task {
                    await model.moveItemToTrash(pendingItem)
                    itemPendingTrash = nil
                }
            }

            Button("Cancel", role: .cancel) {
                itemPendingTrash = nil
            }
        } message: {
            if let itemPendingTrash {
                Text(itemPendingTrash.name)
            }
        }
    }
}

private struct SidebarView: View {
    @EnvironmentObject private var model: FileBrowserViewModel

    var body: some View {
        List(selection: Binding(
            get: { model.currentURL },
            set: { url in
                if let url {
                    model.navigate(to: url)
                }
            }
        )) {
            Section(SidebarLocation.Group.favorites.rawValue) {
                ForEach(model.sidebarLocations.filter { $0.group == .favorites }) { location in
                    Label(location.name, systemImage: location.systemImage)
                        .tag(location.url)
                        .contextMenu {
                            if location.canRemoveFromFavorites {
                                Button("Remove from Favorites") {
                                    model.removeFavorite(location.url)
                                }
                            }
                        }
                }
            }
            .dropDestination(for: URL.self) { urls, _ in
                model.pinDroppedFavorites(urls)
            }

            Section(SidebarLocation.Group.devices.rawValue) {
                ForEach(model.sidebarLocations.filter { $0.group == .devices }) { location in
                    Label(location.name, systemImage: location.systemImage)
                        .tag(location.url)
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
                        .tag(location.url)
                }
            }
        }
        .listStyle(.sidebar)
        .symbolRenderingMode(.hierarchical)
        .safeAreaInset(edge: .bottom) {
            Toggle(isOn: $model.showHiddenFiles) {
                Label("Hidden", systemImage: "eye.fill")
            }
            .toggleStyle(.button)
            .symbolRenderingMode(.hierarchical)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
        }
    }
}

private struct BrowserToolbar: View {
    @EnvironmentObject private var model: FileBrowserViewModel
    @FocusState private var pathFocused: Bool

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 10) {
                ToolbarButtonGroup {
                    ToolbarIconButton(
                        systemName: "chevron.backward",
                        help: "Go back to the previous folder",
                        isDisabled: !model.canGoBack
                    ) {
                        model.goBack()
                    }

                    ToolbarIconButton(
                        systemName: "chevron.forward",
                        help: "Go forward to the next folder",
                        isDisabled: !model.canGoForward
                    ) {
                        model.goForward()
                    }

                    ToolbarIconButton(
                        systemName: "arrow.up.to.line.compact",
                        help: "Go to the enclosing folder",
                        isDisabled: !model.canGoUp
                    ) {
                        model.goUp()
                    }

                    ToolbarIconButton(
                        systemName: "arrow.clockwise",
                        help: "Reload the current folder"
                    ) {
                        model.reload()
                    }
                }

                ToolbarButtonGroup {
                    ToolbarIconButton(
                        systemName: "folder.badge.plus",
                        help: "Create a new folder in the current folder",
                        isDisabled: !model.canCreateFolder
                    ) {
                        Task { await model.createFolder() }
                    }

                    ToolbarIconButton(
                        systemName: "terminal",
                        help: "Open Terminal at the current folder"
                    ) {
                        model.openCurrentFolderInTerminal()
                    }

                    ToolbarIconButton(
                        systemName: "arrow.up.forward.square",
                        help: "Reveal the selected item in Finder"
                    ) {
                        model.revealSelectedInFinder()
                    }
                }

                ToolbarButtonGroup {
                    ToolbarIconButton(
                        systemName: "network.badge.shield.half.filled",
                        help: "Connect to a network server"
                    ) {
                        model.showConnectToServer()
                    }
                }

                Spacer(minLength: 12)

                HStack(spacing: 6) {
                    Image(systemName: "line.3.horizontal.decrease.circle")
                        .foregroundStyle(.secondary)
                    TextField("Filter current folder", text: $model.filterText)
                        .textFieldStyle(.plain)
                        .frame(width: 220)
                }
                .font(.system(size: 13, weight: .medium))
                .padding(.horizontal, 11)
                .padding(.vertical, 7)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
                .overlay {
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(.separator.opacity(0.6), lineWidth: 1)
                }
                .modernTooltip("Filter items shown in the current folder")
            }
            .symbolRenderingMode(.hierarchical)

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
                .modernTooltip("Copy the selected item path, or the current folder path if nothing is selected")
            }
            .symbolRenderingMode(.hierarchical)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(.background)
            .overlay {
                RoundedRectangle(cornerRadius: 7)
                    .stroke(.separator, lineWidth: 1)
            }
            .macOS26GlassPanel()
        }
        .padding(12)
        .background(.bar)
        .onExitCommand {
            pathFocused = false
        }
    }
}

private struct ToolbarButtonGroup<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        HStack(spacing: 4) {
            content
        }
        .padding(3)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(.separator.opacity(0.55), lineWidth: 1)
        }
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
}

private struct FileTableView: View {
    @EnvironmentObject private var model: FileBrowserViewModel
    @Binding var renameItem: FileItem?
    @Binding var renameText: String
    @Binding var itemPendingTrash: FileItem?

    var body: some View {
        ZStack {
            Table(model.filteredItems, selection: Binding(
                get: { model.selectedItemIDs },
                set: { model.selectedItemIDs = $0 }
            )) {
                TableColumn("Name") { item in
                    HStack(spacing: 8) {
                        FileItemIcon(item: item)

                        Text(item.name)
                            .lineLimit(1)

                        Spacer(minLength: 0)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .opacity(model.isCut(item) ? 0.45 : 1)
                    .overlay { rowClickTarget(for: item) }
                    .draggable(item.url)
                }
                .width(min: 260, ideal: 360)

                TableColumn("Kind") { item in
                    Text(item.displayKind)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .overlay { rowClickTarget(for: item) }
                }
                .width(min: 120, ideal: 180)

                TableColumn("Size") { item in
                    Text(item.displaySize)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .overlay { rowClickTarget(for: item) }
                }
                .width(min: 80, ideal: 110)

                TableColumn("Modified") { item in
                    Text(item.modifiedAt.map(Self.dateFormatter.string(from:)) ?? "")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .overlay { rowClickTarget(for: item) }
                }
                .width(min: 150, ideal: 180)
            }
            .contextMenu(forSelectionType: FileItem.ID.self) { selection in
                Button("Open") {
                    model.selectedItemIDs = selection
                    model.openSelected()
                }

                Button("Cut") {
                    model.selectedItemIDs = selection
                    model.cutSelectedItems()
                }
                .disabled(!canCut(selection: selection))

                Button("Rename") {
                    startRename(selection: selection)
                }
                .disabled(!canEdit(selection: selection))

                Button("Move to Trash", role: .destructive) {
                    startTrash(selection: selection)
                }
                .disabled(!canEdit(selection: selection))

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
            } else if model.filteredItems.isEmpty {
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
        guard let id = selection.first, let item = model.items.first(where: { $0.id == id }) else {
            return
        }

        model.selectedItemIDs = [id]
        itemPendingTrash = item
    }

    private func pinFolder(selection: Set<FileItem.ID>) {
        guard let id = selection.first else {
            return
        }

        model.selectedItemIDs = [id]
        model.pinSelectedFolderToFavorites()
    }

    private func canPin(selection: Set<FileItem.ID>) -> Bool {
        guard let id = selection.first, let item = model.items.first(where: { $0.id == id }) else {
            return false
        }

        return model.canPinFolder(item)
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

    private var emptyDescription: String {
        if !model.filterText.isEmpty {
            return "The current-folder filter did not match loaded items."
        }

        if model.isBrowsingNetwork {
            return "No local SMB servers or mounted network volumes were found. Use Connect to Server for a known address."
        }

        return "This folder is empty or unavailable."
    }

    private func rowClickTarget(for item: FileItem) -> some View {
        TableCellClickTarget { mode in
            model.select(item, mode: mode)
        } onOpen: {
            model.selectedItemIDs = [item.id]
            model.openSelected()
        }
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()
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
                Text("\(model.filteredItems.count) of \(model.items.count) items")
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

private extension View {
    @ViewBuilder
    func macOS26GlassPanel() -> some View {
        if #available(macOS 26.0, *) {
            self.glassEffect(.regular, in: RoundedRectangle(cornerRadius: 7))
        } else {
            self
        }
    }
}
