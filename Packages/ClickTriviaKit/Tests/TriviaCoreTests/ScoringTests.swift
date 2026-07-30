import Foundation
import Testing
@testable import TriviaCore

@Suite("Curva del bonus velocità")
struct SpeedBonusCurveTests {
    let curve = SpeedBonusCurve.default

    @Test("Nessun bonus nella parte iniziale")
    func quietLeadIn() {
        #expect(curve.level(atFraction: 0) == 0)
        #expect(curve.level(atFraction: 0.1) == 0)
    }

    @Test("Picco pieno a metà finestra")
    func peak() {
        #expect(curve.level(atFraction: curve.peakMoment) == 1.0)
    }

    @Test("Livello intermedio tra lead-in e picco")
    func warmup() {
        let mid = (curve.quietLeadIn + curve.peakPosition) / 2
        let level = curve.level(atFraction: mid)
        #expect(level > 0)
        #expect(level < 1)
    }

    @Test("Decadimento dopo il picco fino alla coda")
    func decay() {
        let afterPeak = curve.level(atFraction: 0.75)
        #expect(afterPeak < 1.0)
        #expect(curve.level(atFraction: 1.0) == curve.tailLevel)
        #expect(curve.level(atFraction: 2.0) == curve.tailLevel)
    }
}

@Suite("Calcolo del punteggio")
struct ScoreCalculatorTests {
    @Test("Risposta errata: sempre zero, mai punti negativi")
    func wrongAnswer() {
        let calculator = ScoreCalculator(rules: .default)
        #expect(calculator.points(isCorrect: false, elapsedFraction: 0.5) == 0)
    }

    @Test("Modalità solo correttezza: la velocità non conta")
    func accuracyOnly() {
        let calculator = ScoreCalculator(rules: .accuracyOnly)
        let early = calculator.points(isCorrect: true, elapsedFraction: 0.2)
        let late = calculator.points(isCorrect: true, elapsedFraction: 0.9)
        #expect(early == late)
        #expect(early == ScoringRules.accuracyOnly.basePointsPerCorrectAnswer)
    }

    @Test("Bonus massimo al picco della curva")
    func peakBonus() {
        let rules = ScoringRules(
            basePointsPerCorrectAnswer: 100,
            speedBonus: .curve(.default, maxBonusPoints: 50)
        )
        let calculator = ScoreCalculator(rules: rules)
        #expect(calculator.points(isCorrect: true, elapsedFraction: 0.5) == 150)
        #expect(calculator.points(isCorrect: true, elapsedFraction: 0.05) == 100)
    }

    @Test("Tempo non misurato (preferenza illimitata): solo punti base")
    func unlimitedTime() {
        let calculator = ScoreCalculator(rules: .default)
        #expect(
            calculator.points(isCorrect: true, elapsedFraction: nil)
                == ScoringRules.default.basePointsPerCorrectAnswer
        )
    }
}
