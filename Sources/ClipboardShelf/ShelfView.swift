import AppKit
import SwiftUI

struct ShelfView: View {
    @ObservedObject var store: ClipboardStore
    @ObservedObject var app: AppDelegate

    @State private var query = ""
    @State private var filter: KindFilter = .all
    @State private var scope: TimeScope = .oneDay
    @State private var selectedIDs: [UUID] = []
    @State private var imagePreview: ImagePreviewItem?

    private var entries: [ClipboardEntry] {
        store.filteredEntries(query: query, filter: filter, scope: scope)
    }

    var body: some View {
        GeometryReader { geometry in
            let compactHeight = geometry.size.height < 330
            let compactWidth = geometry.size.width < 320
            let showFilters = geometry.size.width >= 360
            let showIdleFooter = !compactHeight || !entries.isEmpty

            VStack(spacing: 0) {
                topBar(isCompact: compactWidth)
                searchAndFilters(showFilters: showFilters)
                Divider()
                content
                if showIdleFooter || !selectedIDs.isEmpty {
                    Divider()
                    footer
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 280, idealWidth: 380, minHeight: 220, idealHeight: 500)
        .background(Color(nsColor: .windowBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color(nsColor: .separatorColor).opacity(0.45), lineWidth: 1)
        )
        .overlay(alignment: .bottomTrailing) {
            WindowResizeHandle()
                .frame(width: 18, height: 18)
                .padding(3)
        }
        .onAppear {
            app.updateShelfSelectionState(hasSelection: !selectedIDs.isEmpty)
        }
        .onDisappear {
            app.updateShelfSelectionState(hasSelection: false)
        }
        .onChange(of: selectedIDs) { _, newValue in
            app.updateShelfSelectionState(hasSelection: !newValue.isEmpty)
        }
        .onChange(of: app.clearShelfSelectionRequest) {
            selectedIDs.removeAll()
        }
        .onChange(of: app.confirmShelfSelectionRequest) {
            confirmSelection()
        }
        .sheet(item: $imagePreview) { item in
            ImagePreviewView(item: item)
        }
    }

    private func topBar(isCompact: Bool) -> some View {
        HStack(spacing: 6) {
            Text("cc-pear")
                .font(.system(size: 14, weight: .semibold))
                .lineLimit(1)

            if !isCompact {
                Text(store.isPaused ? "已暂停" : "\(scope.title)")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            Button {
                app.takeScreenshotToClipboard()
            } label: {
                Image(systemName: app.isTakingScreenshot ? "camera.fill" : "camera.viewfinder")
            }
            .help("截图到剪贴板，也可以在应用运行时按下 Command + 2")
            .disabled(app.isTakingScreenshot)

            Button {
                store.isPaused.toggle()
            } label: {
                Image(systemName: store.isPaused ? "play.fill" : "pause.fill")
            }
            .help(store.isPaused ? "继续记录" : "暂停记录")

            Button {
                app.isPinned.toggle()
            } label: {
                Image(systemName: app.isPinned ? "pin.fill" : "pin")
            }
            .help(app.isPinned ? "取消固定" : "固定小窗")

            Button {
                app.showSettings()
            } label: {
                Image(systemName: "gearshape")
            }
            .help("设置")

            Button {
                app.forceClosePopover()
            } label: {
                Image(systemName: "xmark")
            }
            .help("关闭")

            Button {
                app.quit()
            } label: {
                Image(systemName: "power")
            }
            .help("退出应用")
        }
        .buttonStyle(.borderless)
        .font(.system(size: 13))
        .padding(.horizontal, 10)
        .frame(height: 28)
    }

    private func searchAndFilters(showFilters: Bool) -> some View {
        VStack(spacing: 4) {
            searchField

            if showFilters {
                VStack(spacing: 4) {
                    Picker("", selection: $scope) {
                        ForEach(TimeScope.allCases) { item in
                            Text(item.title).tag(item)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(maxWidth: .infinity)

                    Picker("", selection: $filter) {
                        ForEach(KindFilter.allCases) { item in
                            Text(item.title).tag(item)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.bottom, showFilters ? 5 : 3)
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("搜索内容、应用或文件名", text: $query)
                .textFieldStyle(.plain)
        }
        .padding(.horizontal, 8)
        .frame(height: 26)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 7))
    }

    @ViewBuilder
    private var content: some View {
        if entries.isEmpty {
            VStack(spacing: 10) {
                Image(systemName: "doc.on.clipboard")
                    .font(.system(size: 30))
                    .foregroundStyle(.secondary)
                Text(emptyText)
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(entries) { entry in
                        EntryRow(
                            entry: entry,
                            selectionIndex: selectionIndex(for: entry)
                        ) {
                            toggleSelection(entry)
                        } onCopy: {
                            store.copyToPasteboard(entry)
                        } onFavorite: {
                            store.toggleFavorite(entry)
                        } onDelete: {
                            selectedIDs.removeAll { $0 == entry.id }
                            store.delete(entry)
                        } onOpenImage: {
                            if let path = entry.imagePath {
                                imagePreview = ImagePreviewItem(path: path, title: entry.maskedPreview)
                            }
                        } onEditImage: {
                            if let path = entry.imagePath {
                                app.showImageEditor(path: path, title: entry.maskedPreview)
                            }
                        }
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 7)
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 8) {
            if selectedIDs.isEmpty {
                Text("点卡片选择顺序 · 选好按 Enter 或右键")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            } else {
                Button {
                    confirmSelection()
                } label: {
                    Label("Enter 确认", systemImage: "return")
                }
                .keyboardShortcut(.defaultAction)
                .help("按 Enter 或右键确认后，到目标位置按 Command+V 按顺序粘贴")

                Text("然后到目标位置按 Command+V")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Button {
                    selectedIDs.removeAll()
                } label: {
                    Image(systemName: "xmark.circle")
                }
                .help("清空选择")
            }

            Spacer()
            Text(selectedIDs.isEmpty ? "\(entries.count) 条" : "已选 \(selectedIDs.count)")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
    }

    private var selectedEntries: [ClipboardEntry] {
        selectedIDs.compactMap { id in
            store.entries.first { $0.id == id }
        }
    }

    private func selectionIndex(for entry: ClipboardEntry) -> Int? {
        selectedIDs.firstIndex(of: entry.id).map { $0 + 1 }
    }

    private func toggleSelection(_ entry: ClipboardEntry) {
        if let index = selectedIDs.firstIndex(of: entry.id) {
            selectedIDs.remove(at: index)
        } else {
            selectedIDs.append(entry.id)
        }
    }

    private func confirmSelection() {
        let entries = selectedEntries
        guard !entries.isEmpty else { return }
        app.confirmOrderedEntriesForManualPaste(entries)
    }

    private var emptyText: String {
        if store.isPaused {
            return "记录已暂停"
        }
        switch scope {
        case .oneDay:
            return "最近一天还没有复制内容"
        case .sevenDays:
            return "七天内还没有记录"
        case .favorites:
            return "还没有收藏内容"
        }
    }
}

private struct EntryRow: View {
    let entry: ClipboardEntry
    let selectionIndex: Int?
    let onToggleSelection: () -> Void
    let onCopy: () -> Void
    let onFavorite: () -> Void
    let onDelete: () -> Void
    let onOpenImage: () -> Void
    let onEditImage: () -> Void

    var body: some View {
        ZStack(alignment: .topTrailing) {
            HStack(alignment: .top, spacing: 8) {
                Button(action: onToggleSelection) {
                    ZStack {
                        Circle()
                            .fill(selectionIndex == nil ? Color(nsColor: .controlBackgroundColor) : Color.accentColor)
                            .frame(width: 22, height: 22)
                        if let selectionIndex {
                            Text("\(selectionIndex)")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.white)
                        } else {
                            Circle()
                                .stroke(Color.secondary.opacity(0.55), lineWidth: 1)
                                .frame(width: 22, height: 22)
                        }
                    }
                }
                .buttonStyle(.plain)
                .help("按顺序选择")

                RoundedRectangle(cornerRadius: 2)
                    .fill(Color(hex: entry.sourceColorHex))
                    .frame(width: 3)

                thumbnail

                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Text(entry.sourceAppName)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Color(hex: entry.sourceColorHex))
                            .lineLimit(1)

                        Text(entry.kind.title)
                            .font(.system(size: 11))
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .frame(minWidth: 34)
                            .background(Color(nsColor: .controlBackgroundColor))
                            .clipShape(RoundedRectangle(cornerRadius: 5))

                        Spacer(minLength: 4)
                    }

                    HStack(alignment: .top, spacing: 7) {
                        Text(entry.createdAt.shortTimeText)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .frame(width: 34, alignment: .leading)

                        Text(entry.maskedPreview)
                            .font(.system(size: 12))
                            .lineLimit(3)
                            .textSelection(.enabled)
                            .foregroundStyle(.primary)
                    }
                }
                .padding(.trailing, entry.kind == .image ? 96 : 72)
            }
            .contentShape(Rectangle())
            .onTapGesture(perform: onToggleSelection)

            actionButtons
                .padding(.top, 8)
                .padding(.trailing, 8)
        }
        .padding(8)
        .background(selectionIndex == nil ? Color(nsColor: .textBackgroundColor) : Color.accentColor.opacity(0.09))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color(nsColor: .separatorColor).opacity(0.35), lineWidth: 1)
        )
    }

    private var actionButtons: some View {
        HStack(spacing: 8) {
            if entry.kind == .image {
                Button(action: onEditImage) {
                    Image(systemName: "pencil")
                }
                .help("编辑图片")
            }

            Button(action: onFavorite) {
                Image(systemName: entry.isFavorite ? "star.fill" : "star")
                    .foregroundStyle(entry.isFavorite ? Color.yellow : Color.secondary)
            }
            .help(entry.isFavorite ? "取消收藏" : "收藏，永久保留")

            Button(action: onDelete) {
                Image(systemName: "trash")
            }
            .help("删除")

            Button(action: onCopy) {
                Image(systemName: "doc.on.doc")
            }
            .help("复制原始内容")
        }
        .buttonStyle(.borderless)
        .frame(width: entry.kind == .image ? 92 : 68, alignment: .trailing)
    }

    @ViewBuilder
    private var thumbnail: some View {
        switch entry.kind {
        case .image:
            if let path = entry.imagePath, let image = NSImage(contentsOfFile: path) {
                Button(action: onOpenImage) {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 42, height: 42)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
                .help("放大图片")
            } else {
                fallbackIcon("photo")
            }
        case .link:
            fallbackIcon("link")
        case .file:
            fallbackIcon("folder")
        case .text:
            fallbackIcon("text.alignleft")
        case .richText:
            fallbackIcon("doc.richtext")
        }
    }

    private func fallbackIcon(_ name: String) -> some View {
        Image(systemName: name)
            .font(.system(size: 20))
            .foregroundStyle(.secondary)
            .frame(width: 42, height: 42)
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

private struct ImagePreviewItem: Identifiable {
    let id = UUID()
    let path: String
    let title: String
}

private struct ImagePreviewView: View {
    @Environment(\.dismiss) private var dismiss
    let item: ImagePreviewItem

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Text(item.title.isEmpty ? "图片预览" : item.title)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)

                Spacer()

                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.borderless)
                .help("关闭")
            }
            .padding(.horizontal, 14)
            .frame(height: 38)

            Divider()

            Group {
                if let image = NSImage(contentsOfFile: item.path) {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFit()
                        .padding(14)
                } else {
                    VStack(spacing: 8) {
                        Image(systemName: "photo")
                            .font(.system(size: 30))
                        Text("图片已不可用")
                            .font(.system(size: 13))
                    }
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(minWidth: 520, idealWidth: 720, maxWidth: 920, minHeight: 360, idealHeight: 520, maxHeight: 720)
            .background(Color(nsColor: .textBackgroundColor))
        }
    }
}

private extension Color {
    init(hex: String) {
        let trimmed = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        var value: UInt64 = 0
        Scanner(string: trimmed).scanHexInt64(&value)

        let red = Double((value >> 16) & 0xFF) / 255.0
        let green = Double((value >> 8) & 0xFF) / 255.0
        let blue = Double(value & 0xFF) / 255.0
        self.init(red: red, green: green, blue: blue)
    }
}

private struct WindowResizeHandle: NSViewRepresentable {
    func makeNSView(context: Context) -> ResizeHandleView {
        ResizeHandleView()
    }

    func updateNSView(_ nsView: ResizeHandleView, context: Context) {}
}

private final class ResizeHandleView: NSView {
    private var startFrame = NSRect.zero
    private var startLocation = NSPoint.zero

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = 4
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .resizeLeftRight)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        NSColor.secondaryLabelColor.withAlphaComponent(0.35).setStroke()

        let path = NSBezierPath()
        path.lineWidth = 1.2
        for offset in [4.0, 8.0, 12.0] {
            path.move(to: NSPoint(x: bounds.maxX - offset, y: bounds.minY + 2))
            path.line(to: NSPoint(x: bounds.maxX - 2, y: bounds.minY + offset))
        }
        path.stroke()
    }

    override func mouseDown(with event: NSEvent) {
        guard let window else { return }
        startFrame = window.frame
        startLocation = NSEvent.mouseLocation
    }

    override func mouseDragged(with event: NSEvent) {
        guard let window else { return }
        let location = NSEvent.mouseLocation
        let dx = location.x - startLocation.x
        let dy = location.y - startLocation.y
        let minSize = window.minSize

        var frame = startFrame
        frame.size.width = max(minSize.width, startFrame.width + dx)
        frame.size.height = max(minSize.height, startFrame.height - dy)
        frame.origin.y = startFrame.maxY - frame.size.height
        window.setFrame(frame, display: true)
    }
}
