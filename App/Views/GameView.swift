import SwiftUI
import TriviaCore
import TriviaDesign

/// La schermata di gioco. Regole della casa applicate ovunque: esiti per
/// forma+simbolo+testo (mai solo colore), focus VoiceOver spostato a ogni
/// cambio di fase, misuratore del bonus senza lampeggi, Dynamic Type libero
/// di crescere (tutto scorre).
struct GameView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion

    let engine: SoloMatchEngine

    @AccessibilityFocusState private var focus: FocusArea?
    @State private var isConfirmingAbandon = false

    enum FocusArea: Hashable {
        case question
        case outcome
        case result
    }

    private var visual: VisualPreferences {
        appModel.activeProfile.preferences.visual
    }

    private var reduceMotion: Bool {
        systemReduceMotion || visual.reducesEffects
    }

    var body: some View {
        Group {
            switch engine.phase {
            case .idle:
                ProgressView()
            case .presenting(let index):
                questionScreen(index: index, outcome: nil)
            case .reviewing(let index, let outcome):
                questionScreen(index: index, outcome: outcome)
            case .finished(let result):
                MatchEndView(result: result, focus: $focus)
            }
        }
        .onChange(of: engine.phase) { _, newPhase in
            switch newPhase {
            case .presenting: focus = .question
            case .reviewing: focus = .outcome
            case .finished: focus = .result
            case .idle: break
            }
        }
    }

    // MARK: - Domanda

    @ViewBuilder
    private func questionScreen(index: Int, outcome: SoloMatchEngine.AnswerOutcome?) -> some View {
        let question = engine.quiz.questions[index]
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header(index: index)

                if outcome == nil {
                    bonusMeterIfActive
                }

                Text(question.text)
                    .font(.title2.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityLabel(Text(question.speech?.spokenText ?? question.text))
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityFocused($focus, equals: .question)

                optionButtons(for: question, outcome: outcome)

                if outcome == nil {
                    powerUpBar
                } else if let outcome {
                    outcomePanel(outcome, question: question)
                }
            }
            .padding(24)
            .frame(maxWidth: 640)
            .frame(maxWidth: .infinity)
        }
        .confirmationDialog(
            Text("Abbandonare la partita?"),
            isPresented: $isConfirmingAbandon,
            titleVisibility: .visible
        ) {
            Button("Abbandona", role: .destructive) {
                appModel.abandonMatch()
            }
            Button("Continua a giocare", role: .cancel) {}
        } message: {
            Text("Il punteggio di questa partita andrà perso.")
        }
    }

    private func header(index: Int) -> some View {
        HStack {
            Text("Domanda \(index + 1) di \(engine.questionCount)")
                .font(.subheadline.weight(.medium))
            Spacer()
            Label {
                Text("\(engine.totalScore) punti")
            } icon: {
                Image(systemName: "bolt.badge.checkmark")
            }
            .font(.subheadline.weight(.semibold))
            Button {
                isConfirmingAbandon = true
            } label: {
                Image(systemName: "xmark.circle")
                    .font(.title3)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Abbandona partita"))
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    /// Il canale visivo del tempo: aggiornamento a bassa frequenza, la barra
    /// sale e scende con la curva, nessun lampeggio.
    @ViewBuilder
    private var bonusMeterIfActive: some View {
        if case .curve(let curve, _) = engine.configuration.rules.speedBonus,
           let window = engine.personalWindow,
           let start = engine.questionStartDate {
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

    // MARK: - Opzioni

    private func optionButtons(for question: Question, outcome: SoloMatchEngine.AnswerOutcome?) -> some View {
        VStack(spacing: 12) {
            ForEach(engine.visibleOptions(for: question)) { option in
                optionButton(option, question: question, outcome: outcome)
            }
        }
    }

    private func optionButton(
        _ option: AnswerOption,
        question: Question,
        outcome: SoloMatchEngine.AnswerOutcome?
    ) -> some View {
        Button {
            engine.submitAnswer(option.id)
        } label: {
            HStack {
                Text(option.text)
                    .font(.body.weight(.medium))
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                if let outcome {
                    // A esito noto, gli stati si leggono per simbolo e forma.
                    if option.id == outcome.correctOptionID {
                        Image(systemName: OutcomeSymbol.circuitClosedSystemImage)
                            .accessibilityHidden(true)
                    } else if option.id == outcome.selectedOptionID {
                        Image(systemName: OutcomeSymbol.circuitBrokenSystemImage)
                            .accessibilityHidden(true)
                    }
                }
            }
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(TriviaTheme.color(.surface, palette: visual.palette, increasedContrast: visual.prefersHighContrast))
            )
            .overlay {
                if let outcome, option.id == outcome.correctOptionID {
                    RoundedRectangle(cornerRadius: 14)
                        .strokeBorder(
                            TriviaTheme.color(.circuitClosed, palette: visual.palette, increasedContrast: visual.prefersHighContrast),
                            lineWidth: 2
                        )
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(outcome != nil)
        .accessibilityLabel(accessibilityLabel(for: option, outcome: outcome))
    }

    private func accessibilityLabel(
        for option: AnswerOption,
        outcome: SoloMatchEngine.AnswerOutcome?
    ) -> Text {
        let base = option.speech?.spokenText ?? option.text
        guard let outcome else { return Text(base) }
        if option.id == outcome.correctOptionID {
            return Text("\(base). Risposta esatta")
        }
        if option.id == outcome.selectedOptionID {
            return Text("\(base). La tua risposta, sbagliata")
        }
        return Text(base)
    }

    // MARK: - Power-up

    @ViewBuilder
    private var powerUpBar: some View {
        let owned = engine.inventory.owned
        if !owned.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Power-up")
                    .font(.footnote.weight(.medium))
                    .accessibilityHidden(true)
                HStack(spacing: 12) {
                    ForEach(owned) { entry in
                        powerUpButton(entry.kind, count: entry.count)
                    }
                }
            }
        }
    }

    private func powerUpButton(_ kind: PowerUpKind, count: Int) -> some View {
        let descriptor = PowerUpCatalog.descriptor(for: kind)
        return Button {
            try? engine.useHidePowerUp(kind)
        } label: {
            Label {
                Text("\(descriptor?.name ?? kind.identifier) × \(count)")
            } icon: {
                Image(systemName: "wand.and.stars")
            }
            .font(.subheadline.weight(.medium))
            .padding(.horizontal, 12)
            .frame(minHeight: 44)
        }
        .buttonStyle(.bordered)
        .accessibilityLabel(Text("\(descriptor?.name ?? kind.identifier), disponibili \(count)"))
        .accessibilityHint(Text(descriptor?.detail ?? ""))
    }

    // MARK: - Esito

    private func outcomePanel(_ outcome: SoloMatchEngine.AnswerOutcome, question: Question) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            OutcomeBadge(
                isCorrect: outcome.isCorrect,
                palette: visual.palette,
                increasedContrast: visual.prefersHighContrast
            )
            .accessibilityFocused($focus, equals: .outcome)

            if outcome.awardedPoints > 0 {
                Text("+\(outcome.awardedPoints) punti")
                    .font(.title3.weight(.semibold))
            }

            if !outcome.isCorrect,
               let correct = question.options.first(where: { $0.id == outcome.correctOptionID }) {
                Text("La risposta esatta era: \(correct.text)")
                    .font(.body)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let explanation = outcome.explanation {
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

            Button {
                engine.advance()
            } label: {
                let isLast = engine.currentQuestionIndex == engine.questionCount - 1
                Text(isLast ? "Vedi risultato" : "Avanti")
                    .font(.body.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 50)
            }
            .buttonStyle(.borderedProminent)
            .tint(TriviaTheme.color(.accent, palette: visual.palette, increasedContrast: visual.prefersHighContrast))
        }
        .animation(
            MotionTokens.animation(duration: MotionTokens.quick, reduceMotion: reduceMotion),
            value: outcome
        )
    }
}

// MARK: - Fine partita

struct MatchEndView: View {
    @Environment(AppModel.self) private var appModel

    let result: SoloMatchEngine.MatchResult
    let focus: AccessibilityFocusState<GameView.FocusArea?>.Binding

    private var visual: VisualPreferences {
        appModel.activeProfile.preferences.visual
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                ZigZagShape(segments: 5, amplitude: 8)
                    .stroke(
                        TriviaTheme.color(.accent, palette: visual.palette, increasedContrast: visual.prefersHighContrast),
                        style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round)
                    )
                    .frame(maxWidth: 200)
                    .frame(height: 24)
                    .accessibilityHidden(true)

                Text("Partita completata")
                    .font(.largeTitle.bold())
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityFocused(focus, equals: .result)

                Text("\(result.totalScore) punti")
                    .font(.title.weight(.semibold))

                Text("\(result.correctCount) risposte esatte su \(result.questionCount)")
                    .font(.title3)

                if !result.earnedAwards.isEmpty {
                    VStack(spacing: 8) {
                        Text("Power-up guadagnati")
                            .font(.headline)
                            .accessibilityAddTraits(.isHeader)
                        ForEach(Array(result.earnedAwards.enumerated()), id: \.offset) { _, award in
                            let descriptor = PowerUpCatalog.descriptor(for: award.kind)
                            Label {
                                Text(descriptor?.name ?? award.kind.identifier)
                            } icon: {
                                Image(systemName: "wand.and.stars")
                            }
                            .font(.body)
                        }
                    }
                    .padding(16)
                    .background(
                        RoundedRectangle(cornerRadius: 14)
                            .fill(TriviaTheme.color(.surface, palette: visual.palette, increasedContrast: visual.prefersHighContrast))
                    )
                }

                Button {
                    Task {
                        await appModel.finishMatch(result)
                    }
                } label: {
                    Text("Torna all'inizio")
                        .font(.body.weight(.semibold))
                        .frame(maxWidth: 320, minHeight: 50)
                }
                .buttonStyle(.borderedProminent)
                .tint(TriviaTheme.color(.accent, palette: visual.palette, increasedContrast: visual.prefersHighContrast))
            }
            .padding(32)
            .frame(maxWidth: .infinity)
        }
    }
}
