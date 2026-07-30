import Foundation
import TriviaCore

/// Importer per il template .xlsx di Kahoot:
///   riga 9 in poi · B = domanda · C–F = fino a quattro opzioni ·
///   G = tempo (ignorato: qui il tempo è una regola di partita, non della
///   domanda) · H = risposta corretta indicata per numero (1–4).
///
/// Produce una bozza, mai domande finite: ciò che non torna (corretta
/// mancante o multipla, opzioni troppo poche) diventa un problema visibile
/// nell'anteprima di revisione, non uno scarto muto.
public struct KahootTemplateImporter: QuizDraftImporting {
    private enum Column {
        static let question = 2   // B
        static let firstOption = 3 // C
        static let optionCount = 4 // C, D, E, F
        static let correct = 8    // H
    }

    public init() {}

    public var supportedContentTypes: [String] {
        ["org.openxmlformats.spreadsheetml.sheet"]
    }

    public func draft(fromFileNamed fileName: String, data: Data) throws -> QuizDraft {
        let sheet = try XLSXReader.firstSheet(from: data)

        let dataRows = sheet.rows.keys
            .filter { $0 >= KahootLimits.firstDataRow }
            .sorted()

        var questions: [QuestionDraft] = []
        for rowIndex in dataRows {
            let text = sheet.value(row: rowIndex, column: Column.question)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let options = (0..<Column.optionCount).map { offset in
                sheet.value(row: rowIndex, column: Column.firstOption + offset)?
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            }

            // Righe completamente vuote nel range dati: si saltano in pace.
            if text.isEmpty && options.allSatisfy(\.isEmpty) { continue }

            let correctRaw = sheet.value(row: rowIndex, column: Column.correct) ?? ""
            let (correctIndex, notes) = Self.parseCorrectAnswer(
                correctRaw,
                optionCount: Column.optionCount,
                rowIndex: rowIndex
            )

            questions.append(QuestionDraft(
                text: text,
                options: options,
                correctIndex: correctIndex,
                sourceRow: rowIndex,
                importNotes: notes
            ))
        }

        guard !questions.isEmpty else {
            throw ImportError.noQuestionsFound
        }

        let title = (fileName as NSString).deletingPathExtension
        return QuizDraft(
            title: title.isEmpty ? String(localized: "Quiz importato") : title,
            questions: questions
        )
    }

    /// La colonna H può contenere "3", ma anche "2,3" (Kahoot ammette più
    /// corrette; questo gioco ne prevede una sola) o valori strani.
    /// Un solo numero valido → indice; tutto il resto → `nil` + nota che
    /// spiega all'utente cosa c'era scritto e cosa deve decidere.
    private static func parseCorrectAnswer(
        _ raw: String,
        optionCount: Int,
        rowIndex: Int
    ) -> (index: Int?, notes: [String]) {
        // La cella può arrivare come "2" ma anche come "2.0" (cella numerica).
        let numbers = raw
            .split(whereSeparator: { !$0.isNumber && $0 != "." })
            .compactMap { Double($0).map { Int($0) } }
            .filter { (1...optionCount).contains($0) }

        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)

        switch numbers.count {
        case 1:
            return (numbers[0] - 1, [])
        case 0:
            if trimmed.isEmpty {
                return (nil, [])
            }
            return (nil, [String(localized: "Alla riga \(rowIndex) la risposta corretta indicata era «\(trimmed)», che non corrisponde a un'opzione: scegli quella giusta.")])
        default:
            return (nil, [String(localized: "Alla riga \(rowIndex) il file indicava più risposte corrette (\(trimmed)); questo gioco ne prevede una sola: scegli quale tenere.")])
        }
    }
}
