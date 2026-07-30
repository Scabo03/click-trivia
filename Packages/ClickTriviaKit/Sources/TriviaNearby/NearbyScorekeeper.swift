import Foundation
import TriviaCore

/// Il segnapunti dell'organizzatore: puro calcolo, con le regole comuni
/// della partita, separato dal trasporto per essere testabile fino in fondo.
public struct NearbyScorekeeper: Sendable {
    public let rules: ScoringRules
    private var totals: [PlayerProfile.ID: Int] = [:]

    public init(rules: ScoringRules) {
        self.rules = rules
    }

    /// Chi non ha risposto (uscito o rimasto in silenzio) vale come risposta
    /// mancata: zero punti, mai penalità.
    public mutating func score(
        question: Question,
        questionIndex: Int,
        answers: [AnswerPayload],
        roster: [NearbyParticipant]
    ) -> RoundResultsPayload {
        let calculator = ScoreCalculator(rules: rules)
        var entries: [RoundResultEntry] = []

        for participant in roster {
            let answer = answers.first { $0.playerID == participant.id }
            let selected = answer?.selectedOptionID ?? nil
            let isCorrect = selected.map(question.isCorrect) ?? false
            let points = calculator.points(
                isCorrect: isCorrect,
                elapsedFraction: answer?.elapsedFraction ?? nil
            )
            totals[participant.id, default: 0] += points
            entries.append(RoundResultEntry(
                playerID: participant.id,
                nickname: participant.nickname,
                isCorrect: isCorrect,
                points: points,
                totalScore: totals[participant.id, default: 0]
            ))
        }

        entries.sort { $0.totalScore > $1.totalScore }
        return RoundResultsPayload(
            questionIndex: questionIndex,
            correctOptionID: question.correctOptionID,
            entries: entries
        )
    }

    public func total(for playerID: PlayerProfile.ID) -> Int {
        totals[playerID, default: 0]
    }

    /// Classifica finale con ranking "1224": a pari punti, pari posizione.
    public func finalStandings(roster: [NearbyParticipant]) -> FinalResultsPayload {
        let sorted = roster
            .map { participant in
                (participant: participant, total: totals[participant.id, default: 0])
            }
            .sorted { $0.total > $1.total }

        var standings: [FinalStanding] = []
        for (index, item) in sorted.enumerated() {
            let rank: Int
            if index > 0, item.total == sorted[index - 1].total {
                rank = standings[index - 1].rank
            } else {
                rank = index + 1
            }
            standings.append(FinalStanding(
                playerID: item.participant.id,
                nickname: item.participant.nickname,
                totalScore: item.total,
                rank: rank
            ))
        }
        return FinalResultsPayload(standings: standings)
    }
}
