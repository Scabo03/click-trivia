import SwiftUI
import TriviaCore
import TriviaImport

/// L'anteprima di revisione dell'import: l'utente vede e corregge domande,
/// opzioni e risposta corretta **prima** che qualcosa entri nel gioco.
/// I problemi sono esposti con simbolo + testo (mai solo colore), con la
/// riga del foglio d'origine citata; la conferma resta disabilitata finché
/// ci sono errori. Niente scarti muti.
struct ImportReviewView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.dismiss) private var dismiss

    @State private var draft: QuizDraft
    @State private var buildErrorMessage: String?

    init(draft: QuizDraft) {
        _draft = State(initialValue: draft)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Titolo del quiz", text: $draft.title)
                } header: {
                    Text("Quiz")
                } footer: {
                    summaryText
                }

                ForEach($draft.questions) { $question in
                    questionSection($question)
                }
            }
            .formStyle(.grouped)
            .navigationTitle(Text("Rivedi l'import"))
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Aggiungi al gioco") {
                        confirm()
                    }
                    .disabled(!draft.isReadyToConfirm)
                    .accessibilityHint(
                        draft.isReadyToConfirm
                            ? Text("Salva il quiz e lo rende giocabile")
                            : Text("Disponibile quando tutte le domande sono state corrette")
                    )
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annulla") {
                        dismiss()
                    }
                }
            }
            .alert(
                Text("Qualcosa non torna"),
                isPresented: Binding(
                    get: { buildErrorMessage != nil },
                    set: { if !$0 { buildErrorMessage = nil } }
                )
            ) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(buildErrorMessage ?? "")
            }
        }
        #if os(macOS)
        .frame(minWidth: 520, minHeight: 600)
        #endif
    }

    /// Riepilogo sempre aggiornato, letto anche da VoiceOver come stato
    /// complessivo della revisione.
    private var summaryText: Text {
        let total = draft.questions.count
        let toFix = draft.questionsNeedingFixes
        if total == 0 {
            return Text("Nessuna domanda.")
        }
        if toFix == 0 {
            return Text("\(total) domande, tutte pronte. Controlla e conferma: niente entra nel gioco senza il tuo via libera.")
        }
        return Text("\(total) domande, \(toFix) da correggere prima di poter confermare.")
    }

    // MARK: - Sezione domanda

    private func questionSection(_ question: Binding<QuestionDraft>) -> some View {
        let value = question.wrappedValue
        let index = draft.questions.firstIndex { $0.id == value.id } ?? 0

        return Section {
            issueList(for: value)

            TextField("Domanda", text: question.text, axis: .vertical)
                .accessibilityLabel(Text("Testo della domanda \(index + 1)"))

            ForEach(value.options.indices, id: \.self) { optionIndex in
                TextField(
                    "Opzione \(optionIndex + 1)",
                    text: question.options[optionIndex],
                    axis: .vertical
                )
                .accessibilityLabel(Text("Opzione \(optionIndex + 1) della domanda \(index + 1)"))
            }

            Picker("Risposta corretta", selection: question.correctIndex) {
                Text("Da indicare").tag(Int?.none)
                ForEach(value.options.indices, id: \.self) { optionIndex in
                    let text = value.options[optionIndex]
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    if !text.isEmpty {
                        Text("Opzione \(optionIndex + 1): \(text)")
                            .tag(Int?.some(optionIndex))
                    }
                }
            }
            .accessibilityLabel(Text("Risposta corretta della domanda \(index + 1)"))

            Button(role: .destructive) {
                draft.questions.removeAll { $0.id == value.id }
            } label: {
                Label("Rimuovi questa domanda", systemImage: "trash")
            }
            .accessibilityLabel(Text("Rimuovi la domanda \(index + 1)"))
        } header: {
            if let row = value.sourceRow {
                Text("Domanda \(index + 1) di \(draft.questions.count) — riga \(row) del foglio")
            } else {
                Text("Domanda \(index + 1) di \(draft.questions.count)")
            }
        }
    }

    /// I problemi, in testa alla sezione: simbolo diverso per errori e
    /// avvisi, testo completo, etichette pronte per VoiceOver.
    @ViewBuilder
    private func issueList(for question: QuestionDraft) -> some View {
        ForEach(question.issues) { issue in
            Label {
                Text(issue.message)
                    .font(.subheadline)
            } icon: {
                Image(systemName: issue.severity == .error
                    ? "exclamationmark.octagon.fill"
                    : "info.circle")
            }
            .accessibilityLabel(Text(
                issue.severity == .error
                    ? "Da correggere: \(issue.message)"
                    : "Avviso: \(issue.message)"
            ))
        }
    }

    // MARK: - Conferma

    private func confirm() {
        do {
            let quiz = try draft.buildQuiz()
            Task {
                await appModel.saveImportedQuiz(quiz)
                dismiss()
            }
        } catch {
            // Rete di sicurezza: le invarianti di Question hanno fermato
            // qualcosa sfuggito all'anteprima. Si mostra, non si tace.
            buildErrorMessage = String(localized: "Una domanda non è valida: \(error.localizedDescription)")
        }
    }
}
