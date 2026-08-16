import AppKit
import SwiftUI

// MARK: – Treemap Layout

enum TreemapLayout {
    /// Recursively computes `layoutFrame` for every node in the tree.
    static func layout(node: SpaceNode, in rect: CGRect) {
        node.layoutFrame = rect
        guard node.isDirectory, !node.children.isEmpty, node.size > 0,
              rect.width > 2, rect.height > 2 else { return }
        squarify(nodes: node.children, total: node.size, in: rect.insetBy(dx: 1, dy: 1))
    }

    private static func squarify(nodes: [SpaceNode], total: UInt64, in available: CGRect) {
        guard !nodes.isEmpty, total > 0, available.width > 0, available.height > 0 else { return }
        var remaining = nodes
        var current = available
        var remainingTotal = total

        while !remaining.isEmpty && remainingTotal > 0 && current.width > 0 && current.height > 0 {
            var row: [SpaceNode] = []
            var rowTotal: UInt64 = 0
            var prevWorst = Double.infinity

            for (i, node) in remaining.enumerated() {
                row.append(node)
                rowTotal += node.size
                let worst = worstRatio(row: row, rowTotal: rowTotal, total: remainingTotal, in: current)
                if i > 0 && worst > prevWorst {
                    row.removeLast()
                    rowTotal -= node.size
                    break
                }
                prevWorst = worst
            }

            let count = row.count
            placeRow(row: row, rowTotal: rowTotal, remaining: remainingTotal, in: current)
            for n in row where n.isDirectory && !n.children.isEmpty {
                squarify(nodes: n.children, total: n.size, in: n.layoutFrame.insetBy(dx: 1, dy: 1))
            }

            let frac = CGFloat(rowTotal) / CGFloat(remainingTotal)
            if current.width >= current.height {
                let w = current.width * frac
                current = CGRect(x: current.minX + w, y: current.minY, width: current.width - w, height: current.height)
            } else {
                let h = current.height * frac
                current = CGRect(x: current.minX, y: current.minY + h, width: current.width, height: current.height - h)
            }
            remainingTotal -= rowTotal
            remaining = Array(remaining.dropFirst(count))
        }
    }

    private static func worstRatio(row: [SpaceNode], rowTotal: UInt64, total: UInt64, in rect: CGRect) -> Double {
        let isWide = rect.width >= rect.height
        let frac = Double(rowTotal) / Double(total)
        let stripLong = (isWide ? Double(rect.width) : Double(rect.height)) * frac
        let stripShort = isWide ? Double(rect.height) : Double(rect.width)
        var worst = 0.0
        for n in row {
            let tileFrac = Double(n.size) / Double(rowTotal)
            let a = stripLong
            let b = stripShort * tileFrac
            guard a > 0, b > 0 else { continue }
            worst = max(worst, max(a / b, b / a))
        }
        return worst
    }

    private static func placeRow(row: [SpaceNode], rowTotal: UInt64, remaining: UInt64, in rect: CGRect) {
        let isWide = rect.width >= rect.height
        let frac = CGFloat(rowTotal) / CGFloat(remaining)
        if isWide {
            let stripWidth = rect.width * frac
            var y = rect.minY
            for n in row {
                let h = rect.height * CGFloat(n.size) / CGFloat(rowTotal)
                n.layoutFrame = CGRect(x: rect.minX, y: y, width: stripWidth, height: h)
                y += h
            }
        } else {
            let stripHeight = rect.height * frac
            var x = rect.minX
            for n in row {
                let w = rect.width * CGFloat(n.size) / CGFloat(rowTotal)
                n.layoutFrame = CGRect(x: x, y: rect.minY, width: w, height: stripHeight)
                x += w
            }
        }
    }
}

// MARK: – Colorful icon used for the tab + toolbar

struct SpaceAnalyzerIcon: View {
    var size: CGFloat = 13

    var body: some View {
        Canvas { ctx, s in
            let rects: [(CGRect, Color)] = [
                (CGRect(x: 0,            y: 0,            width: s.width * 0.57, height: s.height * 0.57), .blue),
                (CGRect(x: s.width*0.59, y: 0,            width: s.width * 0.41, height: s.height * 0.35), .green),
                (CGRect(x: s.width*0.59, y: s.height*0.37, width: s.width*0.41, height: s.height*0.20), .orange),
                (CGRect(x: 0,            y: s.height*0.59, width: s.width*0.34, height: s.height*0.41), .purple),
                (CGRect(x: s.width*0.36, y: s.height*0.59, width: s.width*0.64, height: s.height*0.41), .red),
            ]
            for (r, c) in rects {
                ctx.fill(Path(roundedRect: r.insetBy(dx: 0.5, dy: 0.5), cornerRadius: 1.5), with: .color(c))
            }
        }
        .frame(width: size, height: size)
    }
}

// MARK: – Main view

struct SpaceAnalyzerView: View {
    @EnvironmentObject private var viewModel: SpaceAnalyzerViewModel
    @EnvironmentObject private var tabs: BrowserTabsViewModel
    @EnvironmentObject private var settings: AppSettings
    @State private var mode: SpaceAnalyzerMode = .allFiles
    @State private var drillPath: [SpaceNode] = []

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            content
            Divider()
            statsBar
        }
        .background(ThemedSurfaceBackground())
        .onAppear { mode = settings.defaultSpaceAnalyzerMode }
        .onChange(of: mode) { _, _ in drillPath.removeAll() }
    }

    // MARK: Toolbar

    private var toolbar: some View {
        HStack(spacing: 10) {
            Image(systemName: "folder")
                .foregroundStyle(.secondary)
            TextField("Root Folder", text: $viewModel.rootPath)
                .textFieldStyle(.plain)
                .disabled(viewModel.isScanning)
                .onSubmit { viewModel.refresh() }

            Picker("Mode", selection: $mode) {
                ForEach(SpaceAnalyzerMode.allCases) { mode in
                    Text(mode.displayName).tag(mode)
                }
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .frame(width: 260)

            if viewModel.isScanning {
                Button("Cancel Scan") { viewModel.cancelScan() }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                    .controlSize(.small)
            } else {
                Button("Scan") { viewModel.refresh() }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(ThemedBarBackground())
    }

    // MARK: Content area

    @ViewBuilder
    private var content: some View {
        switch viewModel.scanState {
        case .idle:
            idleView
        case .scanning(let count):
            scanningView(count: count)
        case .ready(let root):
            treemapView(root: root)
        case .failed(let msg):
            ContentUnavailableView("Scan Failed", systemImage: "exclamationmark.triangle", description: Text(msg))
        }
    }

    private var idleView: some View {
        ContentUnavailableView {
            Label("No Scan", systemImage: "square.3.layers.3d")
        } description: {
            Text("Enter a folder path above and click Refresh to scan disk usage.")
        } actions: {
            Button("Scan Home Folder") {
                viewModel.startScan(url: FileManager.default.homeDirectoryForCurrentUser)
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private func scanningView(count: Int) -> some View {
        VStack(spacing: 16) {
            ProgressView()
                .controlSize(.large)
            Text("Scanning… \(count) items found")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func treemapView(root: SpaceNode) -> some View {
        VStack(spacing: 0) {
            if mode == .drillDown {
                drillDownNavigation(root: root)
                Divider()
            }
            TreemapCanvas(
                root: drillPath.last ?? root,
                mode: mode,
                categories: viewModel.categories,
                tabs: tabs,
                onOpenDirectory: { node in drillPath.append(node) }
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onChange(of: root.id) { _, _ in drillPath.removeAll() }
    }

    private func drillDownNavigation(root: SpaceNode) -> some View {
        HStack(spacing: 8) {
            Button {
                _ = drillPath.popLast()
            } label: {
                Image(systemName: "chevron.left")
            }
            .buttonStyle(.borderless)
            .disabled(drillPath.isEmpty)
            .help("Go to Parent Folder")

            Button(root.name.isEmpty ? root.url.path : root.name) {
                drillPath.removeAll()
            }
            .buttonStyle(.plain)

            ForEach(Array(drillPath.enumerated()), id: \.element.id) { index, node in
                Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                Button(node.name) {
                    drillPath = Array(drillPath.prefix(index + 1))
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
        .font(.callout)
        .padding(.horizontal, 16)
        .padding(.vertical, 7)
        .background(ThemedBarBackground())
    }

    // MARK: Stats bar

    private var statsBar: some View {
        HStack(spacing: 20) {
            if let stats = viewModel.volumeStats {
                Label(
                    "Total: \(ByteCountFormatter.string(fromByteCount: Int64(stats.total), countStyle: .file))",
                    systemImage: "internaldrive"
                )
                Label(
                    "Free: \(ByteCountFormatter.string(fromByteCount: Int64(stats.free), countStyle: .file))",
                    systemImage: "circle.dotted"
                )
                .foregroundStyle(stats.free < stats.total / 10 ? .red : .secondary)
            } else {
                Text("Volume information unavailable").foregroundStyle(.secondary)
            }
            Spacer()
            if case .ready(let root) = viewModel.scanState {
                Text("Scanned: \(ByteCountFormatter.string(fromByteCount: Int64(root.size), countStyle: .file))")
                    .foregroundStyle(.secondary)
            }
        }
        .font(.footnote)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(ThemedBarBackground())
    }
}

// MARK: – Treemap canvas

private struct TreemapCanvas: View {
    let root: SpaceNode
    let mode: SpaceAnalyzerMode
    let categories: FileCategoryService
    let tabs: BrowserTabsViewModel
    let onOpenDirectory: (SpaceNode) -> Void

    @State private var tileList: [(node: SpaceNode, frame: CGRect)] = []
    @State private var canvasSize: CGSize = .zero

    private let minTileArea: CGFloat = 36  // 6×6 px minimum

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                ThemedSurfaceBackground()
                ForEach(tileList, id: \.node.id) { item in
                    TileView(
                        node: item.node,
                        size: item.frame.size,
                        mode: mode,
                        categories: categories,
                        tabs: tabs,
                        onOpenDirectory: onOpenDirectory
                    )
                        .frame(width: item.frame.width, height: item.frame.height)
                        // .position is layout-affecting (unlike .offset), so the tile's
                        // hit region — including its context menu — lands where it renders.
                        .position(x: item.frame.midX, y: item.frame.midY)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .onChange(of: geo.size) { _, size in rebuildLayout(size: size) }
            .onAppear { rebuildLayout(size: geo.size) }
        }
        .onChange(of: root.id) { _, _ in rebuildLayout(size: canvasSize) }
        .onChange(of: mode) { _, _ in rebuildLayout(size: canvasSize) }
    }

    private func rebuildLayout(size: CGSize) {
        canvasSize = size
        guard size.width > 0, size.height > 0 else { return }
        TreemapLayout.layout(node: root, in: CGRect(origin: .zero, size: size))
        tileList = mode == .drillDown
            ? root.children.compactMap { child in
                child.layoutFrame.width * child.layoutFrame.height >= minTileArea ? (child, child.layoutFrame) : nil
            }
            : collectLeaves(node: root)
    }

    private func collectLeaves(node: SpaceNode) -> [(SpaceNode, CGRect)] {
        let area = node.layoutFrame.width * node.layoutFrame.height
        guard area >= minTileArea else { return [] }

        if node.isDirectory && !node.children.isEmpty {
            let childLeaves = node.children.flatMap { collectLeaves(node: $0) }
            if !childLeaves.isEmpty { return childLeaves }
        }
        return [(node, node.layoutFrame)]
    }
}

// MARK: – Individual tile

private struct TileView: View {
    let node: SpaceNode
    let size: CGSize
    let mode: SpaceAnalyzerMode
    let categories: FileCategoryService
    let tabs: BrowserTabsViewModel
    let onOpenDirectory: (SpaceNode) -> Void

    var body: some View {
        let color = node.isDirectory && mode == .drillDown ? folderColor : (node.isDirectory ? categories.directoryColor : categories.color(for: node.url))
        let showLabel = size.width > 40 && size.height > 22
        let shape = FolderTileShape()

        ZStack(alignment: .bottom) {
            color
                .clipShape(node.isDirectory && mode == .drillDown ? AnyShape(shape) : AnyShape(Rectangle()))
                .overlay {
                    if node.isDirectory && mode == .drillDown {
                        shape.stroke(Color(nsColor: .windowBackgroundColor).opacity(0.7), lineWidth: 0.7)
                    } else {
                        Rectangle().stroke(Color(nsColor: .windowBackgroundColor).opacity(0.6), lineWidth: 0.5)
                    }
                }

            if showLabel {
                Text(node.name)
                    .font(.system(size: min(11, size.height * 0.25)))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.5), radius: 2, y: 1)
                    .padding(.horizontal, 3)
                    .padding(.bottom, 2)
                    .frame(maxWidth: size.width - 4)
            }
        }
        .frame(width: size.width, height: size.height)
        .contentShape(Rectangle())
        .onTapGesture(count: 2) {
            if mode == .drillDown && node.isDirectory {
                onOpenDirectory(node)
            }
        }
        .contextMenu {
            Button("Open") {
                NSWorkspace.shared.open(node.url)
            }
            Button("Browse Location") {
                let target = node.isDirectory ? node.url : node.url.deletingLastPathComponent()
                tabs.browseLocation(target)
            }
            Button("Copy Path to Clipboard") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(node.url.path(percentEncoded: false), forType: .string)
            }
        }
        .tileTooltip(tooltip)
    }

    private var folderColor: Color {
        let palette: [Color] = [.blue, .green, .orange, .purple, .red, .yellow, .mint, .indigo]
        let hash = node.url.standardizedFileURL.path.utf8.reduce(UInt64(1_469_598_103_934_665_603)) {
            ($0 ^ UInt64($1)) &* 1_099_511_628_211
        }
        return palette[Int(hash % UInt64(palette.count))].opacity(0.78)
    }

    private var tooltip: String {
        let sizeText = ByteCountFormatter.string(fromByteCount: Int64(node.size), countStyle: .file)
        if node.isDirectory && mode == .drillDown {
            return "\(sizeText)\n\(node.descendantCount) objects\n\(node.name)\n\(node.url.path(percentEncoded: false))"
        }
        return "\(sizeText)\n\(node.name)\n\(node.url.path(percentEncoded: false))"
    }
}

private struct FolderTileShape: Shape {
    func path(in rect: CGRect) -> Path {
        let tabWidth = min(rect.width * 0.42, 56)
        let tabHeight = min(max(3, rect.height * 0.13), 12)
        let radius = min(5, min(rect.width, rect.height) * 0.08)
        var path = Path()
        path.move(to: CGPoint(x: radius, y: tabHeight))
        path.addLine(to: CGPoint(x: 0, y: tabHeight))
        path.addLine(to: CGPoint(x: 0, y: radius))
        path.addQuadCurve(to: CGPoint(x: radius, y: 0), control: .zero)
        path.addLine(to: CGPoint(x: max(radius, tabWidth - radius), y: 0))
        path.addQuadCurve(to: CGPoint(x: tabWidth, y: radius), control: CGPoint(x: tabWidth, y: 0))
        path.addLine(to: CGPoint(x: tabWidth + tabHeight * 0.5, y: tabHeight))
        path.addLine(to: CGPoint(x: rect.width - radius, y: tabHeight))
        path.addQuadCurve(to: CGPoint(x: rect.width, y: tabHeight + radius), control: CGPoint(x: rect.width, y: tabHeight))
        path.addLine(to: CGPoint(x: rect.width, y: rect.height - radius))
        path.addQuadCurve(to: CGPoint(x: rect.width - radius, y: rect.height), control: CGPoint(x: rect.width, y: rect.height))
        path.addLine(to: CGPoint(x: radius, y: rect.height))
        path.addQuadCurve(to: CGPoint(x: 0, y: rect.height - radius), control: CGPoint(x: 0, y: rect.height))
        path.closeSubpath()
        return path
    }
}
