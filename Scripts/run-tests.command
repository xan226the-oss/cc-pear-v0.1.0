#!/bin/zsh
set -euo pipefail

ROOT_DIR="${0:A:h:h}"
TEST_BIN_DIR="$(mktemp -d /tmp/cc-pear-tests.XXXXXX)"
trap 'rm -rf "$TEST_BIN_DIR"' EXIT
cd "$ROOT_DIR"

swiftc -parse-as-library \
  Sources/ClipboardShelf/Utilities.swift \
  Tests/ClipboardShelfTests/ImageStorageTests.swift \
  -framework AppKit \
  -o "$TEST_BIN_DIR/image-storage-tests"
"$TEST_BIN_DIR/image-storage-tests"

swiftc -parse-as-library \
  Sources/ClipboardShelf/AnnotationModels.swift \
  Tests/ClipboardShelfTests/AnnotationModelsTests.swift \
  -framework AppKit \
  -o "$TEST_BIN_DIR/annotation-model-tests"
"$TEST_BIN_DIR/annotation-model-tests"

swiftc -parse-as-library \
  Sources/ClipboardShelf/Utilities.swift \
  Sources/ClipboardShelf/AnnotationModels.swift \
  Sources/ClipboardShelf/AnnotationRenderer.swift \
  Tests/ClipboardShelfTests/AnnotationRendererTests.swift \
  -framework AppKit \
  -o "$TEST_BIN_DIR/annotation-renderer-tests"
"$TEST_BIN_DIR/annotation-renderer-tests"

swiftc -parse-as-library \
  Sources/ClipboardShelf/Utilities.swift \
  Sources/ClipboardShelf/AnnotationModels.swift \
  Sources/ClipboardShelf/AnnotationRenderer.swift \
  Sources/ClipboardShelf/ImageEditorStore.swift \
  Tests/ClipboardShelfTests/ImageEditorStoreTests.swift \
  -framework AppKit \
  -framework Combine \
  -o "$TEST_BIN_DIR/image-editor-store-tests"
"$TEST_BIN_DIR/image-editor-store-tests"

swiftc -parse-as-library \
  Sources/ClipboardShelf/CanvasTransform.swift \
  Tests/ClipboardShelfTests/CanvasTransformTests.swift \
  -framework AppKit \
  -o "$TEST_BIN_DIR/canvas-transform-tests"
"$TEST_BIN_DIR/canvas-transform-tests"

swiftc -parse-as-library \
  Sources/ClipboardShelf/ScreenshotRestorePolicy.swift \
  Tests/ClipboardShelfTests/ScreenshotRestorePolicyTests.swift \
  -o "$TEST_BIN_DIR/screenshot-restore-policy-tests"
"$TEST_BIN_DIR/screenshot-restore-policy-tests"

swiftc -parse-as-library \
  Sources/ClipboardShelf/Models.swift \
  Sources/ClipboardShelf/RecentScreenshotSelector.swift \
  Tests/ClipboardShelfTests/RecentScreenshotSelectorTests.swift \
  -o "$TEST_BIN_DIR/recent-screenshot-selector-tests"
"$TEST_BIN_DIR/recent-screenshot-selector-tests"

swiftc -parse-as-library \
  Sources/ClipboardShelf/PopoverPresentationPolicy.swift \
  Tests/ClipboardShelfTests/PopoverPresentationPolicyTests.swift \
  -o "$TEST_BIN_DIR/popover-presentation-policy-tests"
"$TEST_BIN_DIR/popover-presentation-policy-tests"

swiftc -parse-as-library \
  Sources/ClipboardShelf/Utilities.swift \
  Sources/ClipboardShelf/AnnotationModels.swift \
  Sources/ClipboardShelf/AnnotationRenderer.swift \
  Sources/ClipboardShelf/ImageEditorStore.swift \
  Sources/ClipboardShelf/CanvasTransform.swift \
  Sources/ClipboardShelf/AnnotationCanvasView.swift \
  Sources/ClipboardShelf/ImageEditorView.swift \
  Tests/ClipboardShelfTests/ImageEditorViewCompileTests.swift \
  -framework AppKit \
  -framework SwiftUI \
  -framework Combine \
  -framework UniformTypeIdentifiers \
  -o "$TEST_BIN_DIR/image-editor-view-tests"
"$TEST_BIN_DIR/image-editor-view-tests"

swiftc -typecheck \
  $(find Sources/ClipboardShelf -name '*.swift' ! -name 'ClipboardShelfApp.swift' -print) \
  Tests/ClipboardShelfTests/AppDelegateEditorCompileTests.swift \
  -framework AppKit \
  -framework SwiftUI \
  -framework Combine \
  -framework ApplicationServices \
  -framework Carbon

swift build
