import Foundation

/// Una raccolta ordinata di domande, giocabile così com'è.
/// In Fase 0 le domande sono incorporate nel quiz: è il formato più semplice
/// da salvare in locale e da trasferire in blocco (Multipeer o CloudKit).
public struct Quiz: Identifiable, Codable, Hashable, Sendable {
    public typealias ID = EntityID<Quiz>

    public let id: ID
    public var title: String
    public var summary: String?
    public var questions: [Question]

    /// Regole di punteggio suggerite dall'autore del quiz; la partita può
    /// adottarle o sostituirle (in solitaria il giocatore fa come vuole).
    public var suggestedRules: ScoringRules?

    public init(
        id: ID = ID(),
        title: String,
        summary: String? = nil,
        questions: [Question] = [],
        suggestedRules: ScoringRules? = nil
    ) {
        self.id = id
        self.title = title
        self.summary = summary
        self.questions = questions
        self.suggestedRules = suggestedRules
    }
}
