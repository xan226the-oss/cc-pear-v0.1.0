# Recent Screenshots Editor Sidebar Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 打开图片编辑器时，自动在左侧加载最新 10 张系统截图，并允许在不丢失未保存标注的前提下直接切换。

**Architecture:** 新建一个纯数据选择器，负责从 `ClipboardEntry` 中筛选、去重并限制最近系统截图；`ClipboardStore` 提供该快照；`ImageEditorStore` 将快照与现有编辑会话合并，重用已有 session 以保留标注。`AppDelegate` 在每次打开编辑器时执行一次同步，现有 `ImageEditorView` 继续渲染 `sessions`。

**Tech Stack:** Swift 6、SwiftUI、AppKit、项目自带 `swiftc` 测试脚本、Swift Package Manager。

## Global Constraints

- 只自加载 `sourceBundleID == "com.apple.screencapture"` 且 `kind == .image` 的历史项。
- 默认最多 10 张，保持剪贴板历史中的最新在前顺序。
- 切换时不弹保存确认，每张图的标注、撤销栈和 dirty 状态必须保留。
- 无效路径、不存在的文件和重复路径不进入自动列表。
- 当前手动打开的图片即使不是系统截图，也必须留在编辑器中并被选中。
- 不新增搜索、分组、删除历史或自定义数量。

---

### Task 1: 最近系统截图选择器

**Files:**
- Create: `Sources/ClipboardShelf/RecentScreenshotSelector.swift`
- Create: `Tests/ClipboardShelfTests/RecentScreenshotSelectorTests.swift`
- Modify: `Scripts/run-tests.command`
- Modify: `Sources/ClipboardShelf/ClipboardStore.swift`

**Interfaces:**
- Consumes: `[ClipboardEntry]`、`limit: Int`、`fileExists: (String) -> Bool`。
- Produces: `RecentScreenshotReference(path: String, title: String)` 以及 `ClipboardStore.recentScreenshots(limit:) -> [RecentScreenshotReference]`。

- [ ] **Step 1: 写失败测试**

在 `RecentScreenshotSelectorTests.swift` 构造 12 个系统截图项、1 个普通图片项、1 个无效路径项和 1 个重复路径项，调用：

```swift
let result = RecentScreenshotSelector.select(
    from: entries,
    limit: 10,
    fileExists: { $0 != "/missing.png" }
)

try expect(result.count == 10, "selector did not enforce the ten-item limit")
try expect(result.map(\.path) == expectedNewestPaths, "selector changed newest-first order")
try expect(!result.contains { $0.path == "/copied.png" }, "selector included a non-screenshot image")
try expect(!result.contains { $0.path == "/missing.png" }, "selector included a missing file")
```

将该测试加入 `Scripts/run-tests.command`，编译时包含 `Models.swift` 和新选择器文件。

- [ ] **Step 2: 运行测试并确认正确失败**

Run: `./Scripts/run-tests.command`

Expected: FAIL，原因是 `RecentScreenshotSelector.swift` 或 `RecentScreenshotSelector` 尚不存在，而不是测试语法错误。

- [ ] **Step 3: 实现最小选择逻辑**

`RecentScreenshotSelector.swift` 定义：

```swift
import Foundation

struct RecentScreenshotReference: Equatable {
    let path: String
    let title: String
}

enum RecentScreenshotSelector {
    static func select(
        from entries: [ClipboardEntry],
        limit: Int = 10,
        fileExists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }
    ) -> [RecentScreenshotReference] {
        guard limit > 0 else { return [] }
        var seen = Set<String>()
        var result: [RecentScreenshotReference] = []
        for entry in entries where entry.kind == .image && entry.sourceBundleID == "com.apple.screencapture" {
            guard let rawPath = entry.imagePath else { continue }
            let path = URL(fileURLWithPath: rawPath).standardizedFileURL.resolvingSymlinksInPath().path
            guard fileExists(path), seen.insert(path).inserted else { continue }
            result.append(.init(path: path, title: entry.maskedPreview))
            if result.count == limit { break }
        }
        return result
    }
}
```

在 `ClipboardStore` 中新增：

```swift
func recentScreenshots(limit: Int = 10) -> [RecentScreenshotReference] {
    RecentScreenshotSelector.select(from: entries, limit: limit)
}
```

- [ ] **Step 4: 运行测试并确认通过**

Run: `./Scripts/run-tests.command`

Expected: `RecentScreenshotSelectorTests passed`，其他现有测试仍全部通过。

- [ ] **Step 5: 提交 Task 1**

```bash
git add Sources/ClipboardShelf/RecentScreenshotSelector.swift Sources/ClipboardShelf/ClipboardStore.swift Tests/ClipboardShelfTests/RecentScreenshotSelectorTests.swift Scripts/run-tests.command
git commit -m "Add recent screenshot selection"
```

### Task 2: 安全同步编辑会话

**Files:**
- Modify: `Sources/ClipboardShelf/ImageEditorStore.swift`
- Modify: `Tests/ClipboardShelfTests/ImageEditorStoreTests.swift`
- Modify: `Scripts/run-tests.command`

**Interfaces:**
- Consumes: `prepare(recentScreenshots:selectedPath:selectedTitle:)`，其中最近截图来自 Task 1 的 `[RecentScreenshotReference]`。
- Produces: 最新在前的 `sessions`，以及指向手动打开图片的 `selectedSessionID`。

- [ ] **Step 1: 写失败测试**

在 `ImageEditorStoreTests.swift` 新增两个用例：

```swift
private static func prepareLoadsRecentScreenshotsAndSelectsRequestedImage() throws {
    let store = ImageEditorStore(output: RecordingOutput())
    store.prepare(
        recentScreenshots: [
            .init(path: "/tmp/new.png", title: "New"),
            .init(path: "/tmp/old.png", title: "Old")
        ],
        selectedPath: "/tmp/old.png",
        selectedTitle: "Old"
    )
    try expect(store.sessions.map(\.imagePath) == ["/tmp/new.png", "/tmp/old.png"], "recent screenshot order changed")
    try expect(store.selectedSession?.imagePath == "/tmp/old.png", "requested image was not selected")
}

private static func preparePreservesDirtySessionState() throws {
    let store = ImageEditorStore(output: RecordingOutput())
    let id = store.enqueue(path: "/tmp/dirty.png", title: "Dirty")
    store.apply(.add(.rectangle(id: UUID(), rect: CGRect(x: 0, y: 0, width: 8, height: 8), style: .default)))
    store.prepare(
        recentScreenshots: [.init(path: "/tmp/new.png", title: "New")],
        selectedPath: "/tmp/new.png",
        selectedTitle: "New"
    )
    try expect(store.session(id: id)?.isDirty == true, "sync discarded a dirty session")
    try expect(store.session(id: id)?.annotations.count == 1, "sync discarded annotations")
}
```

更新 `Scripts/run-tests.command` 的 `ImageEditorStoreTests` 编译输入，加入 `Models.swift` 和 `RecentScreenshotSelector.swift`。

- [ ] **Step 2: 运行测试并确认正确失败**

Run: `./Scripts/run-tests.command`

Expected: FAIL with `value of type 'ImageEditorStore' has no member 'prepare'`.

- [ ] **Step 3: 实现会话合并**

在 `ImageEditorStore` 中新增：

```swift
func prepare(
    recentScreenshots: [RecentScreenshotReference],
    selectedPath: String,
    selectedTitle: String
) {
    let selectedPath = canonicalPath(selectedPath)
    var byPath = Dictionary(uniqueKeysWithValues: sessions.map { ($0.imagePath, $0) })
    var orderedPaths: [String] = []

    for reference in recentScreenshots {
        let path = canonicalPath(reference.path)
        if byPath[path] == nil {
            byPath[path] = ImageEditSession(imagePath: path, title: reference.title)
        }
        if !orderedPaths.contains(path) { orderedPaths.append(path) }
    }

    if byPath[selectedPath] == nil {
        byPath[selectedPath] = ImageEditSession(imagePath: selectedPath, title: selectedTitle)
    }
    if !orderedPaths.contains(selectedPath) { orderedPaths.insert(selectedPath, at: 0) }

    for session in sessions where session.isDirty && !orderedPaths.contains(session.imagePath) {
        orderedPaths.append(session.imagePath)
    }

    sessions = orderedPaths.compactMap { byPath[$0] }
    selectedSessionID = byPath[selectedPath]?.id
    selectedAnnotationID = nil
}

private func canonicalPath(_ path: String) -> String {
    URL(fileURLWithPath: path).standardizedFileURL.resolvingSymlinksInPath().path
}
```

同时让 `enqueue(path:title:)` 复用 `canonicalPath(_:)`，不改变它的现有行为。

- [ ] **Step 4: 运行测试并确认通过**

Run: `./Scripts/run-tests.command`

Expected: `ImageEditorStoreTests passed`，且其他测试无回归。

- [ ] **Step 5: 提交 Task 2**

```bash
git add Sources/ClipboardShelf/ImageEditorStore.swift Tests/ClipboardShelfTests/ImageEditorStoreTests.swift Scripts/run-tests.command
git commit -m "Sync recent screenshots into editor sessions"
```

### Task 3: 打开编辑器时加载侧边栏并发布新版

**Files:**
- Modify: `Sources/ClipboardShelf/AppDelegate.swift`
- Modify: `Tests/ClipboardShelfTests/AppDelegateEditorCompileTests.swift`
- Create: `Tests/ClipboardShelfTests/EditorLaunchWiringTests.swift`
- Modify: `Scripts/run-tests.command`
- Modify: `README.md`

**Interfaces:**
- Consumes: `ClipboardStore.recentScreenshots(limit:)` 和 `ImageEditorStore.prepare(recentScreenshots:selectedPath:selectedTitle:)`。
- Produces: 每次 `showImageEditor(path:title:)` 打开时都刷新的最近 10 张截图侧边栏。

- [ ] **Step 1: 写失败的接线测试**

新建 `EditorLaunchWiringTests.swift`，检查打开编辑器的真实入口已经调用最近截图同步：

```swift
import Foundation

@main
enum EditorLaunchWiringTests {
    static func main() throws {
        let source = try String(contentsOfFile: "Sources/ClipboardShelf/AppDelegate.swift", encoding: .utf8)
        guard source.contains("recentScreenshots: store.recentScreenshots(limit: 10)") else {
            throw WiringFailure()
        }
        print("EditorLaunchWiringTests passed")
    }
}

private struct WiringFailure: Error {}
```

将该测试加入 `Scripts/run-tests.command`。运行 `./Scripts/run-tests.command`，预期 FAIL with `WiringFailure`，因为 `showImageEditor` 仍调用旧的 `enqueue`。`AppDelegateEditorCompileTests.swift` 保持现有公共入口编译检查。

- [ ] **Step 2: 更新 `showImageEditor` 接线**

将原来的单张入队：

```swift
editorStore.enqueue(path: path, title: title.isEmpty ? "图片" : title)
```

替换为：

```swift
editorStore.prepare(
    recentScreenshots: store.recentScreenshots(limit: 10),
    selectedPath: path,
    selectedTitle: title.isEmpty ? "图片" : title
)
```

不修改 `ImageEditorView.thumbnailRail`：现有界面已支持缩略图、选中高亮、dirty 标记和点击切换。

- [ ] **Step 3: 更新用户文档**

在 `README.md` 的图片编辑说明中增加：

```markdown
- 打开图片编辑器时，左侧会显示最近 10 张系统截图，可直接切换；每张图的未保存标注独立保留。
```

- [ ] **Step 4: 运行完整验证**

Run:

```bash
./Scripts/run-tests.command
swift build -c release -Xswiftc -warnings-as-errors
git diff --check
```

Expected: 所有测试打印 `passed`，Debug 和 Release 构建成功，`git diff --check` 无输出。

- [ ] **Step 5: 重建并安装 App**

Run:

```bash
./Scripts/build-app.command
osascript -e 'tell application id "app.cc-pear" to quit'
mv /Applications/cc-pear.app /tmp/cc-pear-before-recent-sidebar.app
ditto ./cc-pear.app /Applications/cc-pear.app
open /Applications/cc-pear.app
cmp ./cc-pear.app/Contents/MacOS/cc-pear /Applications/cc-pear.app/Contents/MacOS/cc-pear
codesign --verify --deep --strict /Applications/cc-pear.app
```

Expected: `cmp` 和 `codesign` 退出码均为 0，新 App 正在运行。若 `/tmp/cc-pear-before-recent-sidebar.app` 已存在，必须先选择新的明确备份路径，不覆盖已有备份。

- [ ] **Step 6: 提交并推送**

```bash
git add Sources/ClipboardShelf/AppDelegate.swift Tests/ClipboardShelfTests/AppDelegateEditorCompileTests.swift Tests/ClipboardShelfTests/EditorLaunchWiringTests.swift Scripts/run-tests.command README.md
git commit -m "Show recent screenshots in image editor"
GIT_TERMINAL_PROMPT=0 git push origin main
gh api repos/xan226the-oss/cc-pear-v0.1.0/commits/main --jq '{sha:.sha,message:.commit.message}'
```

Expected: 远端 `main` 的 SHA 等于本地 `git rev-parse HEAD`，提交信息为 `Show recent screenshots in image editor`。
