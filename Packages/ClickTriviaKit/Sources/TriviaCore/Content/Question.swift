import Foundation

/// Una domanda: solo testo, risposta multipla con **una sola** opzione
/// corretta. Di norma quattro opzioni, ma l'invariante ammette da 3 a 6
/// (il minimo di 3 esclude per costruzione il vero/falso).
///
/// La domanda non sa nulla dei power-up: nascondere opzioni è una meccanica
/// di partita, applicata altrove sullo stato di gioco.
public struct Question: Identifiable, Codable, Hashable, Sendable {
    public typealias ID = EntityID<Question>

    public enum ValidationError: Error, Equatable, Sendable {
        case invalidAnswerCount(Int)
        case duplicateOptionIDs
        case correctOptionNotFound
        case emptyText
    }

    /// Numero di opzioni ammesso: 3...6 (4 è la norma).
    public static let allowedOptionCount = 3...6

    public let id: ID
    public var text: String
    public private(set) var options: [AnswerOption]
    public private(set) var correctOptionID: AnswerOption.ID

    /// Spiegazione della risposta, opzionale ma di alto valore didattico:
    /// prevista fin da subito nel modello.
    public var explanation: String?

    /// Metadati per la lettura vocale della domanda nel suo insieme.
    public var speech: SpeechMetadata?

    public var category: String?
    public var difficulty: Difficulty?

    public init(
        id: ID = ID(),
        text: String,
        options: [AnswerOption],
        correctOptionID: AnswerOption.ID,
        explanation: String? = nil,
        speech: SpeechMetadata? = nil,
        category: String? = nil,
        difficulty: Difficulty? = nil
    ) throws {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw ValidationError.emptyText
        }
        guard Self.allowedOptionCount.contains(options.count) else {
            throw ValidationError.invalidAnswerCount(options.count)
        }
        guard Set(options.map(\.id)).count == options.count else {
            throw ValidationError.duplicateOptionIDs
        }
        guard options.contains(where: { $0.id == correctOptionID }) else {
            throw ValidationError.correctOptionNotFound
        }
        self.id = id
        self.text = trimmed
        self.options = options
        self.correctOptionID = correctOptionID
        self.explanation = explanation
        self.speech = speech
        self.category = category
        self.difficulty = difficulty
    }

    public func isCorrect(_ optionID: AnswerOption.ID) -> Bool {
        optionID == correctOptionID
    }

    public var incorrectOptionIDs: [AnswerOption.ID] {
        options.map(\.id).filter { $0 != correctOptionID }
    }
}

extension Question {
    // La decodifica ripassa dall'init che valida: dati corrotti o importati
    // male non possono produrre una domanda senza risposta corretta.
    private enum CodingKeys: String, CodingKey {
        case id, text, options, correctOptionID, explanation, speech, category, difficulty
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            id: container.decode(ID.self, forKey: .id),
            text: container.decode(String.self, forKey: .text),
            options: container.decode([AnswerOption].self, forKey: .options),
            correctOptionID: container.decode(AnswerOption.ID.self, forKey: .correctOptionID),
            explanation: container.decodeIfPresent(String.self, forKey: .explanation),
            speech: container.decodeIfPresent(SpeechMetadata.self, forKey: .speech),
            category: container.decodeIfPresent(String.self, forKey: .category),
            difficulty: container.decodeIfPresent(Difficulty.self, forKey: .difficulty)
        )
    }
}

/// Una singola opzione di risposta.
public struct AnswerOption: Identifiable, Codable, Hashable, Sendable {
    public typealias ID = EntityID<AnswerOption>

    public let id: ID
    public var text: String
    /// Metadati per la lettura vocale della singola opzione.
    public var speech: SpeechMetadata?

    public init(id: ID = ID(), text: String, speech: SpeechMetadata? = nil) {
        self.id = id
        self.text = text
        self.speech = speech
    }
}

/// Metadati per la resa vocale (VoiceOver e lettura automatica): permettono
/// di pronunciare bene sigle, formule, parole straniere.
public struct SpeechMetadata: Codable, Hashable, Sendable {
    /// Testo alternativo da leggere al posto di quello visivo.
    public var spokenText: String?
    /// Codice lingua BCP-47 (es. "en-US") se diverso da quella dell'app.
    public var languageCode: String?
    /// Se `true`, il testo va letto lettera per lettera (sigle, codici).
    public var spellsOut: Bool

    public init(spokenText: String? = nil, languageCode: String? = nil, spellsOut: Bool = false) {
        self.spokenText = spokenText
        self.languageCode = languageCode
        self.spellsOut = spellsOut
    }
}

public enum Difficulty: Int, Codable, CaseIterable, Comparable, Sendable {
    case easy = 1
    case medium = 2
    case hard = 3

    public static func < (lhs: Difficulty, rhs: Difficulty) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}
