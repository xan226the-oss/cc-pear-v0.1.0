import Foundation

@MainActor
func verifyEditorAPI(_ app: AppDelegate) {
    app.showImageEditor(path: "/tmp/example.png", title: "Example")
}
