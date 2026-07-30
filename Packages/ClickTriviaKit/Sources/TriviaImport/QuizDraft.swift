import Foundation
import TriviaCore

/// Una bozza di quiz importato: tutto modificabile, niente ancora valido
/// per forza. Diventa un `Quiz` vero solo passando dall'init validante di
/// `Question`, dopo che l'utente ha visto e corretto.
public struct QuizDraft: Identifiable, Hashable, Sendable {
    public let id: UUID
    public var title: String
    public var questions: [QuestionDraft]

    public init(id: UUID = UUID(), title: String, questions: [QuestionDraft]) {
        self.id = id
        self.title = title
        self.questions = questions
    }

    /// Quante domande hanno ancora errori bloccanti.
    public var questionsNeedingFixes: Int {
        questions.count { draft in
            draft.issues.contains { $0.severity == .error }
        }
    }

    public var isReadyToConfirm: Bool {
        !questions.isEmpty
            && questionsNeedingFixes == 0
            && !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    public func buildQuiz() throws -> Quiz {
        Quiz(
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            questions: try questions.map { try $0.buildQuestion() }
        )
    }
}

/// Un problema di una bozza: gli errori bloccano la conferma, gli avvisi
/// informano. Il testo è già pronto per l'interfaccia e per VoiceOver.
public struct DraftIssue: Identifiable, Hashable, Sendable {
    public enum Severity: Hashable, Sendable {
        case error
        case warning
    }

    public let severity: Severity
    public let message: String
    public var id: String { message }

    public init(severity: Severity, message: String) {
        self.severity = severity
        self.message = message
    }
}

/// Una domanda in bozza: campi liberi, problemi calcolati sullo stato
/// attuale, più le note lasciate dall'importer su ciò che ha dovuto
/// interpretare (es. più risposte corrette nel file).
public struct QuestionDraft: Identifiable, Hashable, Sendable {
    public let id: UUID
    public var text: String
    /// Le opzioni come slot editabili; le vuote vengono scartate alla
    /// costruzione finale.
    public var options: [String]
    /// Indice (in `options`) della risposta corretta; `nil` = da indicare.
    public var correctIndex: Int?
    /// Riga del foglio di origine, per messaggi rintracciabili.
    public let sourceRow: Int?
    /// Note dell'importer, mostrate come avvisi.
    public var importNotes: [String]

    public init(
        id: UUID = UUID(),
        text: String,
        options: [String],
        correctIndex: Int?,
        sourceRow: Int? = nil,
        importNotes: [String] = []
    ) {
        self.id = id
        self.text = text
        self.options = options
        self.correctIndex = correctIndex
        self.sourceRow = sourceRow
        self.importNotes = importNotes
    }

    private var trimmedText: String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Le opzioni non vuote, con il loro indice originale.
    private var filledOptions: [(index: Int, text: String)] {
        options.enumerated()
            .map { ($0.offset, $0.element.trimmingCharacters(in: .whitespacesAndNewlines)) }
            .filter { !$0.1.isEmpty }
    }

    /// I problemi correnti, ricalcolati a ogni modifica dell'utente.
    public var issues: [DraftIssue] {
        var result: [DraftIssue] = []

        if trimmedText.isEmpty {
            result.append(DraftIssue(
                severity: .error,
                message: String(localized: "La domanda è vuota.")
            ))
        }

        let filled = filledOptions
        if filled.count < Question.allowedOptionCount.lowerBound {
            result.append(DraftIssue(
                severity: .error,
                message: String(localized: "Servono almeno tre opzioni di risposta (il vero/falso non è previsto).")
            ))
        }

        let isCorrectValid = correctIndex.map { index in
            filled.contains { $0.index == index }
        } ?? false
        if !isCorrectValid {
            result.append(DraftIssue(
                severity: .error,
                message: String(localized: "Indica quale opzione è la risposta corretta.")
            ))
        }

        let texts = filled.map(\.text)
        if Set(texts).count != texts.count {
            result.append(DraftIssue(
                severity: .warning,
                message: String(localized: "Due o più opzioni hanno lo stesso testo.")
            ))
        }

        if trimmedText.count > KahootLimits.questionMaxLength {
            result.append(DraftIssue(
                severity: .warning,
                message: String(localized: "La domanda supera i \(KahootLimits.questionMaxLength) caratteri del template Kahoot (per questo gioco va bene comunque).")
            ))
        }
        if texts.contains(where: { $0.count > KahootLimits.answerMaxLength }) {
            result.append(DraftIssue(
                severity: .warning,
                message: String(localized: "Un'opzione supera i \(KahootLimits.answerMaxLength) caratteri del template Kahoot (per questo gioco va bene comunque).")
            ))
        }

        result.append(contentsOf: importNotes.map {
            DraftIssue(severity: .warning, message: $0)
        })

        return result
    }

    /// Converte la bozza in una domanda vera passando dall'init validante:
    /// se qualcosa sfuggisse ai controlli dell'anteprima, fallisce qui,
    /// mai in silenzio.
    public func buildQuestion() throws -> Question {
        let filled = filledOptions
        let answerOptions = filled.map { AnswerOption(text: $0.text) }
        guard let correctIndex,
              let position = filled.firstIndex(where: { $0.index == correctIndex }) else {
            throw ImportError.malformedData(
                details: String(localized: "Risposta corretta non indicata.")
            )
        }
        return try Question(
            text: trimmedText,
            options: answerOptions,
            correctOptionID: answerOptions[position].id
        )
    }
}
