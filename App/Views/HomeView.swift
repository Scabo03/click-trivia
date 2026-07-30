import SwiftUI
import TriviaCore
import TriviaDesign
import TriviaImport
import TriviaNearby
import UniformTypeIdentifiers

struct HomeView: View {
    @Environment(AppModel.self) private var appModel
    @State private var isShowingSettings = false
    @State private var isImporting = false
    @State private var pendingDraft: QuizDraft?
    @State private var importErrorMessage: String?

    private static let xlsxType =
        UTType(filenameExtension: "xlsx") ?? .spreadsheet

    private var visual: VisualPreferences {
        appModel.activeProfile.preferences.visual
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 28) {
                ZigZagShape(segments: 7, amplitude: 10)
                    .stroke(
                        TriviaTheme.color(.accent, palette: visual.palette, increasedContrast: visual.prefersHighContrast),
                        style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round)
                    )
                    .frame(maxWidth: 280)
                    .frame(height: 28)
                    .accessibilityHidden(true)

                Text("ClickTrivia")
                    .font(.largeTitle.bold())
                    .accessibilityAddTraits(.isHeader)

                Text("Ciao, \(appModel.activeProfile.nickname)!")
                    .font(.title3)

                quizSection
                nearbySection
                inventorySection

                VStack(spacing: 12) {
                    Button {
                        isImporting = true
                    } label: {
                        Label("Importa quiz (.xlsx)", systemImage: "square.and.arrow.down")
                            .frame(maxWidth: 320, minHeight: 44)
                    }
                    .buttonStyle(.bordered)
                    .accessibilityHint(Text("Legge un file nel formato template Kahoot; potrai rivedere e correggere tutto prima di aggiungerlo al gioco"))

                    Button {
                        isShowingSettings = true
                    } label: {
                        Label("Impostazioni", systemImage: "gearshape")
                            .frame(maxWidth: 320, minHeight: 44)
                    }
                    .buttonStyle(.bordered)
                }
            }
            .padding(32)
            .frame(maxWidth: .infinity)
        }
        .sheet(isPresented: $isShowingSettings) {
            SettingsView()
        }
        .sheet(item: $pendingDraft) { draft in
            ImportReviewView(draft: draft)
        }
        .fileImporter(
            isPresented: $isImporting,
            allowedContentTypes: [Self.xlsxType]
        ) { result in
            handleImport(result)
        }
        .alert(
            Text("Import non riuscito"),
            isPresented: Binding(
                get: { importErrorMessage != nil },
                set: { if !$0 { importErrorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(importErrorMessage ?? "")
        }
    }

    // MARK: - Quiz

    private var quizSection: some View {
        VStack(spacing: 10) {
            Text("Scegli un quiz")
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
            ForEach(appModel.quizzes) { quiz in
                Button {
                    appModel.startSoloMatch(quiz: quiz)
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(quiz.title)
                            .font(.body.weight(.semibold))
                        Text("\(quiz.questions.count) domande")
                            .font(.subheadline)
                    }
                    .padding(.horizontal, 16)
                    .frame(maxWidth: 320, minHeight: 56, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 14)
                            .fill(TriviaTheme.color(.surface, palette: visual.palette, increasedContrast: visual.prefersHighContrast))
                    )
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("\(quiz.title), \(quiz.questions.count) domande"))
                .accessibilityHint(Text("Avvia una partita in solitaria"))
            }
        }
    }

    // MARK: - In presenza

    private var nearbySection: some View {
        VStack(spacing: 10) {
            Text("Insieme, nella stessa stanza")
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
            Text("Fino a \(NearbyConstants.maxPeersPerSession) dispositivi vicini, senza internet.")
                .font(.subheadline)
                .multilineTextAlignment(.center)
            Menu {
                ForEach(appModel.quizzes) { quiz in
                    Button("\(quiz.title) (\(quiz.questions.count) domande)") {
                        appModel.hostNearbyMatch(quiz: quiz)
                    }
                }
            } label: {
                Label("Apri una sala", systemImage: "antenna.radiowaves.left.and.right")
                    .frame(maxWidth: 320, minHeight: 44)
            }
            .buttonStyle(.bordered)
            .accessibilityHint(Text("Scegli il quiz e apri una sala per giocatori vicini"))

            Button {
                appModel.joinNearbyMatch()
            } label: {
                Label("Unisciti a una sala", systemImage: "person.2.wave.2")
                    .frame(maxWidth: 320, minHeight: 44)
            }
            .buttonStyle(.bordered)
            .accessibilityHint(Text("Cerca le sale aperte nelle vicinanze e chiedi di entrare"))
        }
    }

    // MARK: - Inventario

    @ViewBuilder
    private var inventorySection: some View {
        let owned = appModel.activeProfile.inventory.owned
        VStack(spacing: 8) {
            Text("I tuoi power-up")
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
            if owned.isEmpty {
                Text("Ancora nessuno: si guadagnano giocando bene.")
                    .font(.subheadline)
            } else {
                ForEach(owned) { entry in
                    let descriptor = PowerUpCatalog.descriptor(for: entry.kind)
                    Label {
                        Text("\(descriptor?.name ?? entry.kind.identifier) × \(entry.count)")
                    } icon: {
                        Image(systemName: "wand.and.stars")
                    }
                    .font(.subheadline)
                    .accessibilityLabel(Text("\(descriptor?.name ?? entry.kind.identifier), quantità \(entry.count). \(descriptor?.detail ?? "")"))
                }
            }
        }
    }

    // MARK: - Import

    private func handleImport(_ result: Result<URL, any Error>) {
        switch result {
        case .success(let url):
            do {
                pendingDraft = try appModel.makeDraft(from: url)
            } catch let error as ImportError {
                importErrorMessage = message(for: error)
            } catch {
                importErrorMessage = String(localized: "Il file non è leggibile: \(error.localizedDescription)")
            }
        case .failure(let error):
            importErrorMessage = error.localizedDescription
        }
    }

    private func message(for error: ImportError) -> String {
        switch error {
        case .unsupportedFormat:
            String(localized: "Il file non sembra un foglio .xlsx valido. Serve il formato template di Kahoot.")
        case .malformedData(let details):
            details
        case .noQuestionsFound:
            String(localized: "Nel file non ci sono domande dove il template Kahoot le prevede (dalla riga 9 in poi).")
        }
    }
}
