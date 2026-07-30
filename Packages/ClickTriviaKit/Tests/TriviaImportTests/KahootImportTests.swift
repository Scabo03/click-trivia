import Foundation
import Testing
@testable import TriviaImport
import TriviaCore

private let importer = KahootTemplateImporter()

@Suite("Import dal template Kahoot")
struct KahootImportTests {

    @Test("File ben formato: bozza completa e pronta", arguments: [false, true])
    func wellFormedFile(deflated: Bool) throws {
        let data = XLSXFixture.workbook(
            rows: [
                XLSXFixture.Row(
                    question: "Chi inventò la pila?",
                    options: ["Volta", "Galvani", "Faraday", "Marconi"],
                    correct: "1"
                ),
                XLSXFixture.Row(
                    question: "Unità della resistenza?",
                    options: ["Ohm", "Volt", "Ampere", "Watt"],
                    correct: "1"
                ),
            ],
            deflated: deflated
        )

        let draft = try importer.draft(fromFileNamed: "storia.xlsx", data: data)
        #expect(draft.title == "storia")
        #expect(draft.questions.count == 2)
        #expect(draft.questionsNeedingFixes == 0)
        #expect(draft.isReadyToConfirm)
        #expect(draft.questions[0].correctIndex == 0)
        #expect(draft.questions[0].sourceRow == 9)

        let quiz = try draft.buildQuiz()
        #expect(quiz.questions.count == 2)
        #expect(quiz.questions[0].options.count == 4)
    }

    @Test("Più risposte corrette: da scegliere, con nota parlante")
    func multipleCorrectAnswers() throws {
        let data = XLSXFixture.workbook(rows: [
            XLSXFixture.Row(
                question: "Domanda ambigua",
                options: ["A", "B", "C", "D"],
                correct: "2,3"
            ),
        ])

        let draft = try importer.draft(fromFileNamed: "quiz.xlsx", data: data)
        let question = draft.questions[0]
        #expect(question.correctIndex == nil)
        #expect(question.importNotes.count == 1)
        #expect(question.issues.contains { $0.severity == .error })
        #expect(!draft.isReadyToConfirm)
    }

    @Test("Corretta fuori range o assurda: errore visibile, mai scarto muto")
    func nonsenseCorrectAnswer() throws {
        let data = XLSXFixture.workbook(rows: [
            XLSXFixture.Row(
                question: "Domanda",
                options: ["A", "B", "C"],
                correct: "7"
            ),
        ])

        let draft = try importer.draft(fromFileNamed: "quiz.xlsx", data: data)
        #expect(draft.questions.count == 1)
        #expect(draft.questions[0].correctIndex == nil)
        #expect(draft.questions[0].importNotes.count == 1)
    }

    @Test("Due sole opzioni: errore (il vero/falso resta escluso)")
    func twoOptionsOnly() throws {
        let data = XLSXFixture.workbook(rows: [
            XLSXFixture.Row(
                question: "Vero o falso?",
                options: ["Vero", "Falso"],
                correct: "1"
            ),
        ])

        let draft = try importer.draft(fromFileNamed: "quiz.xlsx", data: data)
        let question = draft.questions[0]
        #expect(question.issues.contains { $0.severity == .error })
        #expect(!draft.isReadyToConfirm)
    }

    @Test("Righe vuote nel range dati: saltate senza rumore")
    func emptyRowsSkipped() throws {
        let data = XLSXFixture.workbook(rows: [
            XLSXFixture.Row(question: "Prima", options: ["A", "B", "C"], correct: "1"),
            XLSXFixture.Row(question: "", options: ["", "", "", ""], correct: ""),
            XLSXFixture.Row(question: "Terza", options: ["A", "B", "C"], correct: "2"),
        ])

        let draft = try importer.draft(fromFileNamed: "quiz.xlsx", data: data)
        #expect(draft.questions.count == 2)
        #expect(draft.questions[1].text == "Terza")
        #expect(draft.questions[1].sourceRow == 11)
    }

    @Test("Limiti Kahoot superati: avviso, non blocco")
    func kahootLimitsAsWarnings() throws {
        let longQuestion = String(repeating: "a", count: KahootLimits.questionMaxLength + 1)
        let data = XLSXFixture.workbook(rows: [
            XLSXFixture.Row(
                question: longQuestion,
                options: ["A", "B", "C"],
                correct: "1"
            ),
        ])

        let draft = try importer.draft(fromFileNamed: "quiz.xlsx", data: data)
        let question = draft.questions[0]
        #expect(question.issues.contains { $0.severity == .warning })
        #expect(!question.issues.contains { $0.severity == .error })
        #expect(draft.isReadyToConfirm)
    }

    @Test("File senza domande: errore dichiarato")
    func noQuestions() {
        let data = XLSXFixture.workbook(rows: [])
        #expect(throws: ImportError.noQuestionsFound) {
            _ = try importer.draft(fromFileNamed: "vuoto.xlsx", data: data)
        }
    }

    @Test("File che non è uno zip: formato non supportato")
    func notAZip() {
        let data = Data("ciao, non sono un foglio di calcolo".utf8)
        #expect(throws: ImportError.unsupportedFormat) {
            _ = try importer.draft(fromFileNamed: "finto.xlsx", data: data)
        }
    }
}

@Suite("Correzione in bozza")
struct DraftEditingTests {

    @Test("La correzione dell'utente rende confermabile la bozza")
    func fixingMakesConfirmable() throws {
        let data = XLSXFixture.workbook(rows: [
            XLSXFixture.Row(question: "Domanda", options: ["A", "B", "C", "D"], correct: "1,2"),
        ])
        var draft = try importer.draft(fromFileNamed: "quiz.xlsx", data: data)
        #expect(!draft.isReadyToConfirm)

        draft.questions[0].correctIndex = 1
        draft.questions[0].importNotes = []
        #expect(draft.isReadyToConfirm)

        let quiz = try draft.buildQuiz()
        #expect(quiz.questions[0].options[1].id == quiz.questions[0].correctOptionID)
    }

    @Test("Opzione vuota scartata: l'indice della corretta resta agganciato")
    func emptyOptionDropped() throws {
        let draft = QuestionDraft(
            text: "Domanda",
            options: ["A", "", "B", "C"],
            correctIndex: 2
        )
        #expect(draft.issues.isEmpty)

        let question = try draft.buildQuestion()
        #expect(question.options.count == 3)
        #expect(question.options[1].text == "B")
        #expect(question.correctOptionID == question.options[1].id)
    }

    @Test("Corretta che punta a un'opzione vuota: errore")
    func correctPointingToEmptyOption() {
        let draft = QuestionDraft(
            text: "Domanda",
            options: ["A", "", "B", "C"],
            correctIndex: 1
        )
        #expect(draft.issues.contains { $0.severity == .error })
    }
}
