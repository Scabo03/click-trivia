import Foundation
import Testing
@testable import TriviaNearby
import TriviaCore

private func makeQuestion() -> Question {
    let options = (0..<4).map { AnswerOption(text: "Opzione \($0)") }
    return try! Question(
        text: "Domanda",
        options: options,
        correctOptionID: options[0].id
    )
}

private func makeRoster(_ count: Int) -> [NearbyParticipant] {
    (0..<count).map {
        NearbyParticipant(
            id: PlayerProfile.ID(),
            nickname: "Giocatore \($0 + 1)",
            isHost: $0 == 0
        )
    }
}

@Suite("Segnapunti in presenza")
struct NearbyScorekeeperTests {

    @Test("Regole comuni: corretta con bonus al picco, errata zero, assente zero")
    func roundScoring() {
        let question = makeQuestion()
        let roster = makeRoster(3)
        let rules = ScoringRules(
            basePointsPerCorrectAnswer: 100,
            speedBonus: .curve(.default, maxBonusPoints: 50)
        )
        var keeper = NearbyScorekeeper(rules: rules)

        let results = keeper.score(
            question: question,
            questionIndex: 0,
            answers: [
                AnswerPayload(
                    playerID: roster[0].id, questionIndex: 0,
                    selectedOptionID: question.correctOptionID, elapsedFraction: 0.5
                ),
                AnswerPayload(
                    playerID: roster[1].id, questionIndex: 0,
                    selectedOptionID: question.incorrectOptionIDs[0], elapsedFraction: 0.3
                ),
                // roster[2] non ha risposto.
            ],
            roster: roster
        )

        #expect(results.entries.count == 3)
        let byID = Dictionary(uniqueKeysWithValues: results.entries.map { ($0.playerID, $0) })
        #expect(byID[roster[0].id]?.points == 150)
        #expect(byID[roster[0].id]?.isCorrect == true)
        #expect(byID[roster[1].id]?.points == 0)
        #expect(byID[roster[2].id]?.points == 0)
        // Ordinata per totale decrescente.
        #expect(results.entries[0].playerID == roster[0].id)
        #expect(results.correctOptionID == question.correctOptionID)
    }

    @Test("Totali cumulati tra i turni e classifica con pari merito")
    func totalsAndStandings() {
        let question = makeQuestion()
        let roster = makeRoster(3)
        var keeper = NearbyScorekeeper(rules: .accuracyOnly)

        for index in 0..<2 {
            _ = keeper.score(
                question: question,
                questionIndex: index,
                answers: [
                    AnswerPayload(playerID: roster[0].id, questionIndex: index, selectedOptionID: question.correctOptionID, elapsedFraction: nil),
                    AnswerPayload(playerID: roster[1].id, questionIndex: index, selectedOptionID: question.correctOptionID, elapsedFraction: nil),
                ],
                roster: roster
            )
        }

        let final = keeper.finalStandings(roster: roster)
        #expect(final.standings.count == 3)
        // Pari merito in testa: entrambi primi, il terzo è terzo (ranking 1224).
        #expect(final.standings[0].rank == 1)
        #expect(final.standings[1].rank == 1)
        #expect(final.standings[2].rank == 3)
        #expect(final.standings[2].totalScore == 0)
        #expect(keeper.total(for: roster[0].id) == 2 * ScoringRules.accuracyOnly.basePointsPerCorrectAnswer)
    }

    @Test("Risposte doppie o di estranei: ignorate dal turno")
    func strangersNotScored() {
        let question = makeQuestion()
        let roster = makeRoster(2)
        var keeper = NearbyScorekeeper(rules: .accuracyOnly)

        let results = keeper.score(
            question: question,
            questionIndex: 0,
            answers: [
                AnswerPayload(playerID: PlayerProfile.ID(), questionIndex: 0, selectedOptionID: question.correctOptionID, elapsedFraction: nil),
            ],
            roster: roster
        )
        // L'estraneo non compare: si calcola solo per il roster.
        #expect(results.entries.count == 2)
        #expect(results.entries.allSatisfy { $0.points == 0 })
    }
}

@Suite("Sala e messaggi")
struct RoomAndMessageTests {

    @Test("Capienza: piena a 8, il limite è dichiarato")
    func capacity() {
        var room = RoomState(hostName: "Luca", quizTitle: "Quiz", participants: makeRoster(7))
        #expect(!room.isFull)
        room.participants.append(NearbyParticipant(id: PlayerProfile.ID(), nickname: "Ottavo", isHost: false))
        #expect(room.isFull)
        #expect(room.capacity == NearbyConstants.maxPeersPerSession)
        #expect(NearbyConstants.maxPeersPerSession == 8)
    }

    @Test("Round-trip di codifica dei messaggi")
    func messageCoding() throws {
        let quiz = Quiz.sample
        let configuration = MatchConfiguration(mode: .nearby, quizID: quiz.id, rules: .default, merit: .disabled)
        let payload = AnswerPayload(
            playerID: PlayerProfile.ID(),
            questionIndex: 2,
            selectedOptionID: quiz.questions[0].correctOptionID,
            elapsedFraction: 0.42
        )
        let messages: [NearbyMessage] = [
            .roomUpdated(RoomState(hostName: "Luca", quizTitle: quiz.title, participants: makeRoster(3))),
            .matchBegan(quiz: quiz, configuration: configuration),
            .questionBegan(index: 4),
            .answerSubmitted(payload),
            .answerProgress(answered: 2, total: 5),
            .matchEnded(FinalResultsPayload(standings: [])),
            .hostLeft,
        ]

        for message in messages {
            let data = try JSONEncoder().encode(message)
            _ = try JSONDecoder().decode(NearbyMessage.self, from: data)
        }

        // Il payload della risposta sopravvive intatto al viaggio.
        let data = try JSONEncoder().encode(NearbyMessage.answerSubmitted(payload))
        let decoded = try JSONDecoder().decode(NearbyMessage.self, from: data)
        guard case .answerSubmitted(let roundTripped) = decoded else {
            Issue.record("Messaggio decodificato nel caso sbagliato")
            return
        }
        #expect(roundTripped == payload)
    }

    @Test("Il tipo di servizio rispetta i vincoli Bonjour")
    func serviceType() {
        let type = NearbyConstants.serviceType
        #expect(type.count <= 15)
        #expect(type.allSatisfy { $0.isLowercase || $0.isNumber || $0 == "-" })
    }
}
