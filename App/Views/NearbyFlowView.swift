import SwiftUI
import TriviaCore
import TriviaDesign
import TriviaNearby

/// Il flusso del gioco in presenza. Regola della casa applicata a ogni
/// stato di connessione: sempre una riga di stato **testuale** (mai solo
/// spinner o colore), focus VoiceOver spostato a ogni transizione, e gli
/// annunci sonori/aptici/vocali passano dal FeedbackCenter via controller.
struct NearbyFlowView: View {
    @Environment(AppModel.self) private var appModel

    let controller: NearbyMatchController

    @AccessibilityFocusState private var focus: FocusArea?
    @State private var isConfirmingLeave = false

    enum FocusArea: Hashable {
        case status
        case question
        case review
        case finished
    }

    private var visual: VisualPreferences {
        appModel.activeProfile.preferences.visual
    }

    var body: some View {
        Group {
            switch controller.stage {
            case .browsing:
                browsingScreen
            case .requesting(let hostName):
                waitingScreen(
                    title: String(localized: "Richiesta inviata"),
                    status: String(localized: "In attesa che \(hostName) accetti la tua richiesta.")
                )
            case .lobby:
                lobbyScreen
            case .question(let index):
                questionScreen(index: index, answered: false)
            case .awaitingOthers(let index):
                questionScreen(index: index, answered: true)
            case .review(let results):
                reviewScreen(results)
            case .finished(let final):
                finishedScreen(final)
            case .ended(let reason):
                endedScreen(reason)
            }
        }
        .onChange(of: controller.stage) { _, newStage in
            switch newStage {
            case .question: focus = .question
            case .review: focus = .review
            case .finished: focus = .finished
            default: focus = .status
            }
        }
        .confirmationDialog(
            Text(controller.role == .host ? "Chiudere la sala?" : "Uscire dalla sala?"),
            isPresented: $isConfirmingLeave,
            titleVisibility: .visible
        ) {
            Button(controller.role == .host ? "Chiudi la sala per tutti" : "Esci", role: .destructive) {
                appModel.leaveNearbyMatch()
            }
            Button("Resta", role: .cancel) {}
        } message: {
            if controller.role == .host {
                Text("Chiudendo la sala, la partita termina per tutti i partecipanti.")
            } else {
                Text("Uscendo, la partita continua senza di te.")
            }
        }
    }

    // MARK: - Elementi comuni

    /// La riga di stato: testo sempre presente, primo elemento letto.
    private func statusLine(_ text: String) -> some View {
        Text(text)
            .font(.body)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityFocused($focus, equals: .status)
    }

    private func leaveButton(_ label: String) -> some View {
        Button {
            isConfirmingLeave = true
        } label: {
            Text(label)
                .frame(maxWidth: 320, minHeight: 44)
        }
        .buttonStyle(.bordered)
    }

    private func screenScaffold<Content: View>(
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        ScrollView {
            VStack(spacing: 20) {
                Text(title)
                    .font(.title.bold())
                    .accessibilityAddTraits(.isHeader)
                content()
            }
            .padding(28)
            .frame(maxWidth: 640)
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: - Ricerca sale (ospite)

    private var browsingScreen: some View {
        screenScaffold(title: String(localized: "Sale vicine")) {
            statusLine(
                controller.rooms.isEmpty
                    ? String(localized: "Ricerca di sale vicine in corso. Chiedi all'organizzatore di aprire la sala.")
                    : String(localized: "Trovate \(controller.rooms.count) sale. Scegline una per chiedere di entrare.")
            )
            ForEach(controller.rooms) { room in
                Button {
                    controller.requestJoin(room)
                } label: {
                    Label {
                        Text("Sala di \(room.hostName)")
                            .font(.body.weight(.semibold))
                    } icon: {
                        Image(systemName: "dot.radiowaves.left.and.right")
                    }
                    .padding(.horizontal, 16)
                    .frame(maxWidth: 320, minHeight: 56, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 14)
                            .fill(TriviaTheme.color(.surface, palette: visual.palette, increasedContrast: visual.prefersHighContrast))
                    )
                }
                .buttonStyle(.plain)
                .accessibilityHint(Text("Invia la richiesta di ingresso all'organizzatore"))
            }
            leaveButton(String(localized: "Annulla"))
        }
    }

    private func waitingScreen(title: String, status: String) -> some View {
        screenScaffold(title: title) {
            statusLine(status)
            leaveButton(String(localized: "Annulla"))
        }
    }

    // MARK: - Sala (entrambi)

    private var lobbyScreen: some View {
        screenScaffold(title: String(localized: "Sala di \(controller.room.hostName)")) {
            statusLine(lobbyStatus)

            VStack(spacing: 8) {
                Text("Partecipanti: \(controller.room.participants.count) su \(controller.room.capacity)")
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)
                ForEach(controller.room.participants) { participant in
                    Label {
                        Text(participant.isHost
                            ? "\(participant.nickname) (organizzatore)"
                            : participant.nickname)
                    } icon: {
                        Image(systemName: participant.isHost ? "star.circle" : "person.circle")
                    }
                    .font(.body)
                }
                if controller.room.isFull {
                    Label {
                        Text("Sala piena: il massimo è \(controller.room.capacity) dispositivi.")
                    } icon: {
                        Image(systemName: "person.crop.circle.badge.xmark")
                    }
                    .font(.subheadline)
                }
            }

            if controller.role == .host {
                hostControls
            }

            leaveButton(controller.role == .host
                ? String(localized: "Chiudi la sala")
                : String(localized: "Esci dalla sala"))
        }
    }

    private var lobbyStatus: String {
        if controller.role == .host {
            if controller.room.participants.count < 2 {
                return String(localized: "Quiz: \(controller.room.quizTitle). In attesa che qualcuno chieda di entrare.")
            }
            return String(localized: "Quiz: \(controller.room.quizTitle). Puoi avviare la partita quando il gruppo è al completo.")
        }
        return String(localized: "Quiz: \(controller.room.quizTitle). In attesa che l'organizzatore avvii la partita.")
    }

    @ViewBuilder
    private var hostControls: some View {
        if !controller.pendingRequests.isEmpty {
            VStack(spacing: 10) {
                Text("Richieste di ingresso")
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)
                ForEach(controller.pendingRequests) { request in
                    HStack(spacing: 12) {
                        Text(request.payload.nickname)
                            .font(.body.weight(.medium))
                        Spacer()
                        Button {
                            controller.respond(to: request, accept: true)
                        } label: {
                            Label("Accetta", systemImage: "checkmark.circle.fill")
                                .frame(minHeight: 44)
                        }
                        .buttonStyle(.borderedProminent)
                        .accessibilityLabel(Text("Accetta \(request.payload.nickname)"))
                        Button {
                            controller.respond(to: request, accept: false)
                        } label: {
                            Label("Rifiuta", systemImage: "xmark.circle")
                                .frame(minHeight: 44)
                        }
                        .buttonStyle(.bordered)
                        .accessibilityLabel(Text("Rifiuta \(request.payload.nickname)"))
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 14)
                            .fill(TriviaTheme.color(.surface, palette: visual.palette, increasedContrast: visual.prefersHighContrast))
                    )
                }
            }
        }

        Button {
            controller.startMatch()
        } label: {
            Label("Avvia la partita", systemImage: "bolt.circle.fill")
                .font(.title3.weight(.semibold))
                .frame(maxWidth: 320, minHeight: 56)
        }
        .buttonStyle(.borderedProminent)
        .tint(TriviaTheme.color(.accent, palette: visual.palette, increasedContrast: visual.prefersHighContrast))
        .disabled(!controller.canStartMatch)
        .accessibilityHint(
            controller.canStartMatch
                ? Text("Avvia il quiz per tutti i partecipanti")
                : Text("Disponibile quando in sala ci sono almeno due giocatori")
        )
    }

    // MARK: - Domanda

    @ViewBuilder
    private func questionScreen(index: Int, answered: Bool) -> some View {
        if let question = controller.currentQuestion {
            screenScaffold(title: String(localized: "Domanda \(index + 1) di \(controller.questionCount)")) {
                if answered {
                    statusLine(String(localized: "Risposta inviata. Hanno risposto \(controller.answeredCount) su \(controller.expectedAnswers)."))
                } else {
                    bonusMeterIfActive
                }

                Text(question.text)
                    .font(.title2.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityLabel(Text(question.speech?.spokenText ?? question.text))
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityFocused($focus, equals: .question)

                VStack(spacing: 12) {
                    ForEach(question.options) { option in
                        Button {
                            controller.submitAnswer(option.id)
                        } label: {
                            Text(option.text)
                                .font(.body.weight(.medium))
                                .multilineTextAlignment(.leading)
                                .fixedSize(horizontal: false, vertical: true)
                                .padding(.horizontal, 16)
                                .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
                                .background(
                                    RoundedRectangle(cornerRadius: 14)
                                        .fill(TriviaTheme.color(.surface, palette: visual.palette, increasedContrast: visual.prefersHighContrast))
                                )
                        }
                        .buttonStyle(.plain)
                        .disabled(answered)
                        .accessibilityLabel(Text(option.speech?.spokenText ?? option.text))
                    }
                }

                if controller.role == .host, answered {
                    Button {
                        controller.advance()
                    } label: {
                        Text("Chiudi il turno adesso")
                            .frame(maxWidth: 320, minHeight: 44)
                    }
                    .buttonStyle(.bordered)
                    .accessibilityHint(Text("Chi non ha risposto otterrà zero punti per questa domanda"))
                }

                leaveButton(controller.role == .host
                    ? String(localized: "Chiudi la sala")
                    : String(localized: "Esci dalla sala"))
            }
        }
    }

    @ViewBuilder
    private var bonusMeterIfActive: some View {
        if let configuration = controller.configuration,
           case .curve(let curve, _) = configuration.rules.speedBonus,
           let window = controller.personalWindow,
           let start = controller.questionStartDate {
            TimelineView(.periodic(from: .now, by: 0.25)) { context in
                BonusMeterView(
                    curve: curve,
                    elapsedFraction: context.date.timeIntervalSince(start) / window.seconds,
                    palette: visual.palette,
                    increasedContrast: visual.prefersHighContrast
                )
            }
        }
    }

    // MARK: - Esiti del turno

    private func reviewScreen(_ results: RoundResultsPayload) -> some View {
        let mine = results.entries.first { $0.playerID == appModel.activeProfile.id }
        let question = controller.currentQuestion

        return screenScaffold(title: String(localized: "Esiti del turno")) {
            if let mine {
                OutcomeBadge(
                    isCorrect: mine.isCorrect,
                    palette: visual.palette,
                    increasedContrast: visual.prefersHighContrast
                )
                .accessibilityFocused($focus, equals: .review)
                if mine.points > 0 {
                    Text("+\(mine.points) punti")
                        .font(.title3.weight(.semibold))
                }
            }

            if let question,
               let correct = question.options.first(where: { $0.id == results.correctOptionID }) {
                Text("La risposta esatta era: \(correct.text)")
                    .font(.body)
                    .fixedSize(horizontal: false, vertical: true)
                if let explanation = question.explanation {
                    Text(explanation)
                        .font(.body)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(12)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(TriviaTheme.color(.surface, palette: visual.palette, increasedContrast: visual.prefersHighContrast))
                        )
                        .accessibilityLabel(Text("Spiegazione: \(explanation)"))
                }
            }

            standingsList(
                title: String(localized: "Classifica"),
                rows: results.entries.map { entry in
                    StandingRow(
                        id: entry.playerID,
                        text: "\(entry.nickname): \(entry.totalScore) punti",
                        isCorrect: entry.isCorrect,
                        isMe: entry.playerID == appModel.activeProfile.id
                    )
                }
            )

            if controller.role == .host {
                Button {
                    controller.advance()
                } label: {
                    let isLast = results.questionIndex == controller.questionCount - 1
                    Text(isLast ? "Classifica finale" : "Prossima domanda")
                        .font(.body.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 50)
                }
                .buttonStyle(.borderedProminent)
                .tint(TriviaTheme.color(.accent, palette: visual.palette, increasedContrast: visual.prefersHighContrast))
            } else {
                statusLine(String(localized: "In attesa che l'organizzatore prosegua."))
            }
        }
    }

    private struct StandingRow: Identifiable {
        let id: PlayerProfile.ID
        let text: String
        var isCorrect: Bool?
        let isMe: Bool
    }

    private func standingsList(title: String, rows: [StandingRow]) -> some View {
        VStack(spacing: 8) {
            Text(title)
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
            ForEach(rows) { row in
                Label {
                    Text(row.isMe ? "\(row.text) (tu)" : row.text)
                        .font(row.isMe ? .body.weight(.semibold) : .body)
                } icon: {
                    if let isCorrect = row.isCorrect {
                        Image(systemName: isCorrect
                            ? OutcomeSymbol.circuitClosedSystemImage
                            : OutcomeSymbol.circuitBrokenSystemImage)
                    } else {
                        Image(systemName: "person.circle")
                    }
                }
                .accessibilityLabel(accessibilityText(for: row))
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(TriviaTheme.color(.surface, palette: visual.palette, increasedContrast: visual.prefersHighContrast))
        )
    }

    private func accessibilityText(for row: StandingRow) -> Text {
        var parts = row.isMe ? "\(row.text), sei tu" : row.text
        if let isCorrect = row.isCorrect {
            parts += isCorrect
                ? ", risposta esatta in questo turno"
                : ", risposta sbagliata in questo turno"
        }
        return Text(parts)
    }

    // MARK: - Fine e chiusura

    private func finishedScreen(_ final: FinalResultsPayload) -> some View {
        screenScaffold(title: String(localized: "Classifica finale")) {
            if let mine = final.standings.first(where: { $0.playerID == appModel.activeProfile.id }) {
                Text("Sei arrivato \(ordinal(mine.rank)) con \(mine.totalScore) punti")
                    .font(.title3.weight(.semibold))
                    .multilineTextAlignment(.center)
                    .accessibilityFocused($focus, equals: .finished)
            }

            standingsList(
                title: String(localized: "Tutti i giocatori"),
                rows: final.standings.map { standing in
                    StandingRow(
                        id: standing.playerID,
                        text: "\(standing.rank)º — \(standing.nickname): \(standing.totalScore) punti",
                        isCorrect: nil,
                        isMe: standing.playerID == appModel.activeProfile.id
                    )
                }
            )

            Button {
                appModel.leaveNearbyMatch()
            } label: {
                Text("Torna all'inizio")
                    .font(.body.weight(.semibold))
                    .frame(maxWidth: 320, minHeight: 50)
            }
            .buttonStyle(.borderedProminent)
            .tint(TriviaTheme.color(.accent, palette: visual.palette, increasedContrast: visual.prefersHighContrast))
        }
    }

    private func endedScreen(_ reason: NearbyMatchController.EndReason) -> some View {
        screenScaffold(title: String(localized: "Sala chiusa")) {
            statusLine(message(for: reason))
            Button {
                appModel.leaveNearbyMatch()
            } label: {
                Text("Torna all'inizio")
                    .font(.body.weight(.semibold))
                    .frame(maxWidth: 320, minHeight: 50)
            }
            .buttonStyle(.borderedProminent)
            .tint(TriviaTheme.color(.accent, palette: visual.palette, increasedContrast: visual.prefersHighContrast))
        }
    }

    private func message(for reason: NearbyMatchController.EndReason) -> String {
        switch reason {
        case .hostLeft:
            String(localized: "L'organizzatore ha chiuso la sala. La partita è terminata.")
        case .connectionLost:
            String(localized: "La connessione con la sala è andata persa. Avvicinatevi e riprovate.")
        case .declinedOrFull:
            String(localized: "La richiesta non è stata accettata, oppure la sala è piena: il massimo è \(NearbyConstants.maxPeersPerSession) dispositivi.")
        }
    }

    private func ordinal(_ rank: Int) -> String {
        "\(rank)º"
    }
}
