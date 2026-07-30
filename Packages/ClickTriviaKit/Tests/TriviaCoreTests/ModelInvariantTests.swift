import Foundation
import Testing
@testable import TriviaCore

private func makeOptions(_ count: Int) -> [AnswerOption] {
    (0..<count).map { AnswerOption(text: "Opzione \($0 + 1)") }
}

@Suite("Invarianti della domanda")
struct QuestionInvariantTests {
    @Test("Domanda valida a 4 opzioni")
    func validQuestion() throws {
        let options = makeOptions(4)
        let question = try Question(
            text: "Chi ha inventato la pila?",
            options: options,
            correctOptionID: options[0].id,
            explanation: "Alessandro Volta, nel 1799."
        )
        #expect(question.isCorrect(options[0].id))
        #expect(question.incorrectOptionIDs.count == 3)
    }

    @Test("Il vero/falso è escluso per costruzione (minimo 3 opzioni)")
    func rejectsTrueFalse() {
        let options = makeOptions(2)
        #expect(throws: Question.ValidationError.invalidAnswerCount(2)) {
            _ = try Question(
                text: "Vero o falso?",
                options: options,
                correctOptionID: options[0].id
            )
        }
    }

    @Test("La risposta corretta deve esistere tra le opzioni")
    func rejectsMissingCorrectOption() {
        let options = makeOptions(4)
        #expect(throws: Question.ValidationError.correctOptionNotFound) {
            _ = try Question(
                text: "Domanda?",
                options: options,
                correctOptionID: AnswerOption.ID()
            )
        }
    }

    @Test("La decodifica ripassa dalla validazione")
    func decodingValidates() throws {
        let options = makeOptions(4)
        let valid = try Question(
            text: "Domanda?",
            options: options,
            correctOptionID: options[1].id
        )
        var payload = try JSONSerialization.jsonObject(
            with: JSONEncoder().encode(valid)
        ) as! [String: Any]
        payload["correctOptionID"] = UUID().uuidString
        let corrupted = try JSONSerialization.data(withJSONObject: payload)

        #expect(throws: (any Error).self) {
            _ = try JSONDecoder().decode(Question.self, from: corrupted)
        }
    }
}

@Suite("Inventario power-up")
struct PowerUpInventoryTests {
    @Test("Guadagno e consumo")
    func addAndUse() throws {
        var inventory = PowerUpInventory()
        #expect(inventory.isEmpty)

        inventory.add(.classicHideTwo)
        #expect(inventory.count(of: .classicHideTwo) == 1)

        try inventory.use(.classicHideTwo)
        #expect(inventory.isEmpty)
    }

    @Test("Non si consuma ciò che non si possiede")
    func useUnavailable() {
        var inventory = PowerUpInventory()
        #expect(throws: PowerUpInventory.InventoryError.notAvailable(.classicHideTwo)) {
            try inventory.use(.classicHideTwo)
        }
    }
}

@Suite("Identità del giocatore")
struct PlayerIdentityTests {
    @Test("Rinominare non tocca identità, inventario né storico")
    func renameKeepsIdentity() {
        var profile = PlayerProfile(nickname: "Volta")
        profile.inventory.add(.classicHideTwo)
        profile.progression.totalPoints = 500

        let originalID = profile.id
        profile.nickname = "Dinamo"

        #expect(profile.id == originalID)
        #expect(profile.inventory.count(of: .classicHideTwo) == 1)
        #expect(profile.progression.totalPoints == 500)
    }
}
