import SwiftUI

/// The root of a hosted window. It reads the active tokens from the app model, so the window
/// changes theme live when macOS changes between Light and Dark Mode.
struct ThemedRoot<Content: View>: View {
    @Environment(AppModel.self) private var model
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .environment(\.tokens, model.tokens)
            .preferredColorScheme(model.tokens.colorScheme)
    }
}
