import AppKit
import SwiftUI

struct ImageEditorView: View {
    @ObservedObject var store: ImageEditorStore
    @State private var completionNotice: String?

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            editorContent
            Divider()
            actionBar
        }
        .frame(minWidth: 900, minHeight: 600)
        .background(Color(nsColor: .windowBackgroundColor))
        .alert("编辑失败", isPresented: errorPresented) {
            Button("好") { store.errorMessage = nil }
        } message: {
            Text(store.errorMessage ?? "未知错误")
        }
        .overlay(alignment: .top) {
            if let completionNotice {
                Text(completionNotice)
                    .font(.system(size: 12, weight: .medium))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(.regularMaterial)
                    .clipShape(Capsule())
                    .padding(.top, 48)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
    }

    private var toolbar: some View {
        HStack(spacing: 4) {
            ForEach(AnnotationTool.allCases) { tool in
                Button {
                    store.tool = tool
                    if tool != .select {
                        store.selectedAnnotationID = nil
                    }
                } label: {
                    VStack(spacing: 2) {
                        Image(systemName: tool.symbolName)
                            .font(.system(size: 15, weight: .medium))
                        Text(tool.title)
                            .font(.system(size: 10))
                    }
                    .frame(width: 52, height: 38)
                    .background(store.tool == tool ? Color.accentColor.opacity(0.16) : Color.clear)
                    .clipShape(RoundedRectangle(cornerRadius: 7))
                }
                .buttonStyle(.plain)
                .help(tool.title)
            }

            Spacer()

            if let session = store.selectedSession {
                Text(session.title)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                if session.isDirty {
                    Circle()
                        .fill(Color.orange)
                        .frame(width: 7, height: 7)
                        .help("有未保存修改")
                }
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 52)
    }

    @ViewBuilder
    private var editorContent: some View {
        if store.sessions.isEmpty {
            VStack(spacing: 12) {
                Image(systemName: "photo.badge.plus")
                    .font(.system(size: 42))
                    .foregroundStyle(.secondary)
                Text("截图或从历史记录选择图片后，可在这里标注")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            HSplitView {
                thumbnailRail
                    .frame(minWidth: 116, idealWidth: 132, maxWidth: 160)

                canvas
                    .frame(minWidth: 520, maxWidth: .infinity, maxHeight: .infinity)

                inspector
                    .frame(minWidth: 170, idealWidth: 190, maxWidth: 220)
            }
        }
    }

    private var thumbnailRail: some View {
        ScrollView {
            LazyVStack(spacing: 10) {
                ForEach(store.sessions) { session in
                    Button {
                        store.select(id: session.id)
                    } label: {
                        VStack(alignment: .leading, spacing: 5) {
                            ZStack(alignment: .topTrailing) {
                                if let image = NSImage(contentsOfFile: session.imagePath) {
                                    Image(nsImage: image)
                                        .resizable()
                                        .scaledToFit()
                                        .frame(maxWidth: .infinity, minHeight: 64, maxHeight: 92)
                                        .background(Color.black.opacity(0.06))
                                } else {
                                    Image(systemName: "photo.badge.exclamationmark")
                                        .frame(maxWidth: .infinity, minHeight: 72)
                                        .foregroundStyle(.secondary)
                                }
                                if session.isDirty {
                                    Circle()
                                        .fill(Color.orange)
                                        .frame(width: 8, height: 8)
                                        .padding(5)
                                }
                            }
                            Text(session.title)
                                .font(.system(size: 10))
                                .lineLimit(1)
                        }
                        .padding(6)
                        .background(store.selectedSessionID == session.id ? Color.accentColor.opacity(0.14) : Color.clear)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(
                                    store.selectedSessionID == session.id ? Color.accentColor.opacity(0.7) : Color.secondary.opacity(0.18),
                                    lineWidth: 1
                                )
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(10)
        }
        .background(Color(nsColor: .underPageBackgroundColor))
    }

    @ViewBuilder
    private var canvas: some View {
        if let session = store.selectedSession,
           let image = NSImage(contentsOfFile: session.imagePath) {
            AnnotationCanvasView(
                imageKey: session.imagePath,
                image: image,
                annotations: session.annotations,
                tool: store.tool,
                style: store.style,
                selectedAnnotationID: store.selectedAnnotationID,
                onEdit: { store.apply($0) },
                onSelect: { store.selectedAnnotationID = $0 }
            )
        } else {
            VStack(spacing: 8) {
                Image(systemName: "photo.badge.exclamationmark")
                    .font(.system(size: 32))
                Text("原图已不可用")
            }
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var inspector: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("工具属性")
                .font(.system(size: 13, weight: .semibold))

            if store.tool != .select && store.tool != .mosaic {
                ColorPicker("颜色", selection: colorBinding, supportsOpacity: true)
            }

            if [.rectangle, .arrow, .freehand].contains(store.tool) {
                labeledSlider(
                    title: "线宽",
                    value: Binding(
                        get: { Double(store.style.lineWidth) },
                        set: { store.style.lineWidth = CGFloat($0) }
                    ),
                    range: 1...16,
                    valueText: "\(Int(store.style.lineWidth)) px"
                )
            }

            if store.tool == .text {
                labeledSlider(
                    title: "字号",
                    value: Binding(
                        get: { Double(store.style.fontSize) },
                        set: { store.style.fontSize = CGFloat($0) }
                    ),
                    range: 10...96,
                    valueText: "\(Int(store.style.fontSize)) px"
                )
            }

            if store.tool == .mosaic {
                labeledSlider(
                    title: "马赛克粒度",
                    value: Binding(
                        get: { Double(store.style.mosaicBlockSize) },
                        set: { store.style.mosaicBlockSize = CGFloat($0) }
                    ),
                    range: 6...48,
                    valueText: "\(Int(store.style.mosaicBlockSize)) px"
                )
            }

            Divider()

            Text("操作提示")
                .font(.system(size: 12, weight: .semibold))
            Text("拖动创建标注。选择工具可移动或 Delete 删除。Command + 滚轮缩放，滚轮移动画面。")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Spacer()
        }
        .padding(14)
        .background(Color(nsColor: .underPageBackgroundColor))
    }

    private var actionBar: some View {
        HStack(spacing: 10) {
            Button {
                store.undo()
            } label: {
                Label("撤销", systemImage: "arrow.uturn.backward")
            }
            .disabled(store.selectedSession?.canUndo != true)
            .keyboardShortcut("z", modifiers: .command)

            Button {
                store.redo()
            } label: {
                Label("重做", systemImage: "arrow.uturn.forward")
            }
            .disabled(store.selectedSession?.canRedo != true)
            .keyboardShortcut("z", modifiers: [.command, .shift])

            Button(role: .destructive) {
                store.clear()
            } label: {
                Label("清空标注", systemImage: "eraser")
            }
            .disabled(store.selectedSession?.annotations.isEmpty != false)

            Spacer()

            Button {
                exportCurrent()
            } label: {
                Label("导出", systemImage: "square.and.arrow.down")
            }
            .disabled(store.selectedSession == nil)

            Button {
                if store.completeCurrent() {
                    showNotice("已保存到历史并复制")
                }
            } label: {
                Label("完成并复制", systemImage: "doc.on.clipboard.fill")
            }
            .buttonStyle(.borderedProminent)
            .disabled(store.selectedSession == nil)
        }
        .padding(.horizontal, 14)
        .frame(height: 54)
    }

    private var colorBinding: Binding<Color> {
        Binding(
            get: { Color(nsColor: store.style.color.nsColor) },
            set: { store.style.color = AnnotationColor(NSColor($0)) }
        )
    }

    private var errorPresented: Binding<Bool> {
        Binding(
            get: { store.errorMessage != nil },
            set: { if !$0 { store.errorMessage = nil } }
        )
    }

    private func labeledSlider(
        title: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        valueText: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(title)
                Spacer()
                Text(valueText)
                    .foregroundStyle(.secondary)
            }
            .font(.system(size: 11))
            Slider(value: value, in: range)
        }
    }

    private func exportCurrent() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = "cc-pear-标注.png"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        if store.exportCurrent(to: url) {
            showNotice("已导出")
        }
    }

    private func showNotice(_ text: String) {
        withAnimation { completionNotice = text }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
            withAnimation { completionNotice = nil }
        }
    }
}
