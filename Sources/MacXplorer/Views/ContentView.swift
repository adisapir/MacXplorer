import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var model: FileBrowserViewModel
    @State private var renameItem: FileItem?
    @State private var renameText = ""
    @State private var itemPendingTrash: FileItem?

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
                Task {
                    model.selectedItemID = itemPendingTrash?.id
                    await model.moveSelectedToTrash()
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
                            if location.isPinned {
                                Button("Remove from Favorites") {
                                    model.unpinFavorite(location.url)
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
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom) {
            Toggle(isOn: $model.showHiddenFiles) {
                Label("Hidden", systemImage: "eye")
            }
            .toggleStyle(.button)
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
            HStack(spacing: 8) {
                Button {
                    model.goBack()
                } label: {
                    Image(systemName: "chevron.left")
                }
                .disabled(!model.canGoBack)
                .help("Back")

                Button {
                    model.goForward()
                } label: {
                    Image(systemName: "chevron.right")
                }
                .disabled(!model.canGoForward)
                .help("Forward")

                Button {
                    model.goUp()
                } label: {
                    Image(systemName: "arrow.up")
                }
                .disabled(!model.canGoUp)
                .help("Up")

                Button {
                    model.reload()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .help("Reload")

                Divider()
                    .frame(height: 22)

                Button {
                    Task { await model.createFolder() }
                } label: {
                    Image(systemName: "folder.badge.plus")
                }
                .help("New Folder")

                Button {
                    model.openSelectedInTerminal()
                } label: {
                    Image(systemName: "terminal")
                }
                .help("Open in Terminal")

                Button {
                    model.revealSelectedInFinder()
                } label: {
                    Image(systemName: "arrow.up.forward.app")
                }
                .help("Reveal in Finder")

                Spacer(minLength: 12)

                HStack(spacing: 6) {
                    Image(systemName: "line.3.horizontal.decrease.circle")
                        .foregroundStyle(.secondary)
                    TextField("Filter current folder", text: $model.filterText)
                        .textFieldStyle(.plain)
                        .frame(width: 220)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 7))
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
                .help("Copy Path")
            }
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

private struct FileTableView: View {
    @EnvironmentObject private var model: FileBrowserViewModel
    @Binding var renameItem: FileItem?
    @Binding var renameText: String
    @Binding var itemPendingTrash: FileItem?

    var body: some View {
        ZStack {
            Table(model.filteredItems, selection: Binding(
                get: { model.selectedItemID },
                set: { model.selectedItemID = $0 }
            )) {
                TableColumn("Name") { item in
                    HStack(spacing: 8) {
                        Image(systemName: item.opensInApp ? "folder.fill" : "doc")
                            .foregroundStyle(item.opensInApp ? .blue : .secondary)
                            .frame(width: 18)

                        Text(item.name)
                            .lineLimit(1)
                    }
                    .draggable(item.url)
                }
                .width(min: 260, ideal: 360)

                TableColumn("Kind") { item in
                    Text(item.displayKind)
                        .foregroundStyle(.secondary)
                }
                .width(min: 120, ideal: 180)

                TableColumn("Size") { item in
                    Text(item.displaySize)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                .width(min: 80, ideal: 110)

                TableColumn("Modified") { item in
                    Text(item.modifiedAt.map(Self.dateFormatter.string(from:)) ?? "")
                        .foregroundStyle(.secondary)
                }
                .width(min: 150, ideal: 180)
            }
            .contextMenu(forSelectionType: FileItem.ID.self) { selection in
                Button("Open") {
                    model.selectedItemID = selection.first
                    model.openSelected()
                }

                Button("Rename") {
                    startRename(selection: selection)
                }

                Button("Move to Trash", role: .destructive) {
                    startTrash(selection: selection)
                }

                Divider()

                Button("Add to Favorites") {
                    pinFolder(selection: selection)
                }
                .disabled(!canPin(selection: selection))

                Divider()

                Button("Copy Path") {
                    model.selectedItemID = selection.first
                    model.copySelectedPath()
                }

                Button("Open in Terminal") {
                    model.selectedItemID = selection.first
                    model.openSelectedInTerminal()
                }

                Button("Reveal in Finder") {
                    model.selectedItemID = selection.first
                    model.revealSelectedInFinder()
                }
            } primaryAction: { selection in
                model.selectedItemID = selection.first
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
                    systemImage: model.filterText.isEmpty ? "folder" : "magnifyingglass",
                    description: Text(model.filterText.isEmpty ? "This folder is empty or unavailable." : "The current-folder filter did not match loaded items.")
                )
            }
        }
    }

    private func startRename(selection: Set<FileItem.ID>) {
        guard let id = selection.first, let item = model.items.first(where: { $0.id == id }) else {
            return
        }

        model.selectedItemID = id
        renameItem = item
        renameText = item.name
    }

    private func startTrash(selection: Set<FileItem.ID>) {
        guard let id = selection.first, let item = model.items.first(where: { $0.id == id }) else {
            return
        }

        model.selectedItemID = id
        itemPendingTrash = item
    }

    private func pinFolder(selection: Set<FileItem.ID>) {
        guard let id = selection.first else {
            return
        }

        model.selectedItemID = id
        model.pinSelectedFolderToFavorites()
    }

    private func canPin(selection: Set<FileItem.ID>) -> Bool {
        guard let id = selection.first, let item = model.items.first(where: { $0.id == id }) else {
            return false
        }

        return model.canPinFolder(item)
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

            Text(model.currentURL.path)
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
