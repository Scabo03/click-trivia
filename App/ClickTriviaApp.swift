import SwiftUI
import TriviaAccessibility

@main
struct ClickTriviaApp: App {
    @State private var appModel = AppModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(appModel)
                .environment(appModel.feedback)
                .environment(appModel.visualCues)
        }
        #if os(macOS)
        .defaultSize(width: 720, height: 560)
        #endif
    }
}
