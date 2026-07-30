import SwiftUI
import TriviaCore
import TriviaDesign

/// Radice: casa o partita in corso. La sostituzione integrale della vista
/// (invece di una navigazione impilata) tiene il focus di VoiceOver dove
/// serve: sulla domanda quando si gioca, sulla casa quando si è a casa.
struct RootView: View {
    @Environment(AppModel.self) private var appModel

    var body: some View {
        Group {
            if let nearby = appModel.nearbyMatch {
                NearbyFlowView(controller: nearby)
            } else if let match = appModel.currentMatch {
                GameView(engine: match)
            } else {
                HomeView()
            }
        }
        .background(
            TriviaTheme.color(
                .background,
                palette: appModel.activeProfile.preferences.visual.palette,
                increasedContrast: appModel.activeProfile.preferences.visual.prefersHighContrast
            )
            .ignoresSafeArea()
        )
        .foregroundStyle(
            TriviaTheme.color(
                .primaryText,
                palette: appModel.activeProfile.preferences.visual.palette,
                increasedContrast: appModel.activeProfile.preferences.visual.prefersHighContrast
            )
        )
        .task {
            await appModel.loadOrCreateProfile()
        }
    }
}
