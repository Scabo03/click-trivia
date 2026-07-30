import Foundation
import Testing
@testable import TriviaCore

/// Quiz di prova a opzioni fisse: la prima opzione è sempre la corretta.
private func makeQuiz(questionCount: Int) -> Quiz {
    let questions = (0..<questionCount).map { index -> Question in
        let options = (0..<4).map { AnswerOption(text: "Q\(index) opzione \($0)") }
        return try! Question(
            text: "Domanda \(index)",
            options: options,
            correctOptionID: options[0].id,
            explanation: "Spiegazione \(index)"
        )
    }
    return Quiz(title: "Test", questions: questions)
}

private func correctOption(of question: Question) -> AnswerOption.ID {
    question.correctOptionID
}

private func wrongOption(of question: Question) -> AnswerOption.ID {
    question.incorrectOptionIDs[0]
}

@MainActor
private func makeEngine(
    questionCount: Int = 3,
    merit: MeritRules = .disabled,
    inventory: (inout PowerUpInventory) -> Void = { _ in }
) -> SoloMatchEngine {
    var profile = PlayerProfile(nickname: "Tester")
    profile.preferences.timing = .unlimited
    inventory(&profile.inventory)
    let quiz = makeQuiz(questionCount: questionCount)
    let configuration = MatchConfiguration(
        mode: .soloOffline,
        quizID: quiz.id,
        rules: .accuracyOnly,
        merit: merit
    )
    return SoloMatchEngine(quiz: quiz, configuration: configuration, profile: profile)
}

@Suite("Motore di partita")
@MainActor
struct SoloMatchEngineTests {

    @Test("Flusso completo: eventi, punteggio, risultato")
    func fullFlow() {
        let engine = makeEngine(questionCount: 2)
        var events: [GameEvent] = []
        engine.onEvent = { events.append($0) }

        engine.start()
        #expect(engine.phase == .presenting(questionIndex: 0))
        #expect(events == [.matchStarted, .questionPresented])

        engine.submitAnswer(correctOption(of: engine.quiz.questions[0]))
        #expect(events.last == .circuitClosed)
        guard case .reviewing(0, let outcome) = engine.phase else {
            Issue.record("Fase inattesa: \(engine.phase)")
            return
        }
        #expect(outcome.isCorrect)
        #expect(outcome.awardedPoints == ScoringRules.accuracyOnly.basePointsPerCorrectAnswer)

        engine.advance()
        engine.submitAnswer(wrongOption(of: engine.quiz.questions[1]))
        #expect(events.last == .circuitBroken)
        #expect(engine.streak == 0)

        engine.advance()
        guard case .finished(let result) = engine.phase else {
            Issue.record("Fase inattesa: \(engine.phase)")
            return
        }
        #expect(events.last == .matchEnded)
        #expect(result.correctCount == 1)
        #expect(result.questionCount == 2)
        #expect(result.totalScore == ScoringRules.accuracyOnly.basePointsPerCorrectAnswer)
        #expect(result.session.rounds.count == 2)
    }

    @Test("Merito: la serie frutta il Fusibile, il quiz perfetto il Corto circuito")
    func meritAwards() {
        let merit = MeritRules(streakLength: 2)
        let engine = makeEngine(questionCount: 4, merit: merit)
        var events: [GameEvent] = []
        engine.onEvent = { events.append($0) }

        engine.start()
        for index in 0..<4 {
            engine.submitAnswer(correctOption(of: engine.quiz.questions[index]))
            engine.advance()
        }

        guard case .finished(let result) = engine.phase else {
            Issue.record("Fase inattesa: \(engine.phase)")
            return
        }
        // Serie di 2 e di 4 → due Fusibili; quiz perfetto → un Corto circuito.
        #expect(result.earnedAwards.count == 3)
        #expect(result.earnedAwards.filter { $0.kind == .lightHideOne }.count == 2)
        #expect(result.earnedAwards.filter { $0.kind == .classicHideTwo }.count == 1)
        #expect(result.remainingInventory.count(of: .lightHideOne) == 2)
        #expect(result.remainingInventory.count(of: .classicHideTwo) == 1)
        #expect(events.filter { $0 == .powerUpEarned }.count == 3)
    }

    @Test("Fusibile: nasconde una sbagliata, ne restano tre")
    func lightHideOne() throws {
        let engine = makeEngine(inventory: { $0.add(.lightHideOne) })
        engine.start()

        try engine.useHidePowerUp(.lightHideOne)
        let question = engine.quiz.questions[0]
        #expect(engine.hiddenOptionIDs.count == 1)
        #expect(engine.visibleOptions(for: question).count == 3)
        #expect(engine.visibleOptions(for: question).contains { $0.id == question.correctOptionID })
        #expect(engine.inventory.count(of: .lightHideOne) == 0)
    }

    @Test("Corto circuito: nasconde due sbagliate, ne restano due")
    func classicHideTwo() throws {
        let engine = makeEngine(inventory: { $0.add(.classicHideTwo) })
        engine.start()

        try engine.useHidePowerUp(.classicHideTwo)
        let question = engine.quiz.questions[0]
        #expect(engine.hiddenOptionIDs.count == 2)
        #expect(engine.visibleOptions(for: question).count == 2)
        #expect(engine.visibleOptions(for: question).contains { $0.id == question.correctOptionID })
    }

    @Test("Resta sempre visibile almeno una sbagliata: se non c'è margine, non si consuma")
    func powerUpNotApplicable() throws {
        let engine = makeEngine(inventory: {
            $0.add(.classicHideTwo, count: 2)
        })
        engine.start()

        try engine.useHidePowerUp(.classicHideTwo)
        // Rimane una sola sbagliata visibile: un secondo uso non è applicabile.
        #expect(throws: SoloMatchEngine.EngineError.powerUpNotApplicable) {
            try engine.useHidePowerUp(.classicHideTwo)
        }
        #expect(engine.inventory.count(of: .classicHideTwo) == 1)
    }

    @Test("I power-up usati finiscono nel verbale della risposta")
    func powerUpsRecorded() throws {
        let engine = makeEngine(inventory: { $0.add(.lightHideOne) })
        engine.start()

        try engine.useHidePowerUp(.lightHideOne)
        engine.submitAnswer(correctOption(of: engine.quiz.questions[0]))

        guard case .reviewing = engine.phase else {
            Issue.record("Fase inattesa: \(engine.phase)")
            return
        }
        // Il verbale della prima domanda registra il Fusibile.
        engine.advance()
        engine.submitAnswer(correctOption(of: engine.quiz.questions[1]))
        engine.advance()
        engine.submitAnswer(correctOption(of: engine.quiz.questions[2]))
        engine.advance()

        guard case .finished(let result) = engine.phase else {
            Issue.record("Fase inattesa: \(engine.phase)")
            return
        }
        #expect(result.session.rounds[0].answers[0].powerUpsUsed == [.lightHideOne])
        #expect(result.session.rounds[1].answers[0].powerUpsUsed.isEmpty)
    }

    @Test("Tempi illimitati: nessuna finestra personale")
    func unlimitedTiming() {
        let engine = makeEngine()
        #expect(engine.personalWindow == nil)
    }

    @Test("Tempi estesi: la finestra personale è scalata")
    func extendedTiming() {
        var profile = PlayerProfile(nickname: "Tester")
        profile.preferences.timing = .extended(multiplier: 2)
        let quiz = makeQuiz(questionCount: 1)
        let configuration = MatchConfiguration(mode: .soloOffline, quizID: quiz.id, rules: .default)
        let engine = SoloMatchEngine(quiz: quiz, configuration: configuration, profile: profile)

        let expected = ScoringRules.default.referenceWindow.scaled(by: 2)
        #expect(engine.personalWindow == expected)
    }
}
