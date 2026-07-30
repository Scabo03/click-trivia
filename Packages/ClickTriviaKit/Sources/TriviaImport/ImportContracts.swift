import Foundation
import TriviaCore

/// Fase 2 — Import di contenuti. Principio: un importer non produce mai
/// domande finite, produce una **bozza** (`QuizDraft`) che l'utente vede,
/// corregge e conferma nell'anteprima di revisione. Un file corrotto o mal
/// interpretato non entra mai nel gioco in silenzio: le invarianti di
/// `Question` restano l'ultima barriera, l'anteprima è dove diventano
/// correzione visibile e accessibile.
public protocol QuizDraftImporting: Sendable {
    /// Identificatori UTType dei formati dichiarati.
    var supportedContentTypes: [String] { get }

    /// Decodifica il file in una bozza rivedibile. Lancia solo per problemi
    /// strutturali (file illeggibile); i problemi di contenuto finiscono
    /// dentro la bozza, come questioni da correggere.
    func draft(fromFileNamed fileName: String, data: Data) throws -> QuizDraft
}

public enum ImportError: Error, Equatable, Sendable {
    /// Il file non è nel formato atteso (non è uno zip/xlsx leggibile).
    case unsupportedFormat
    /// Struttura riconosciuta ma contenuto non interpretabile.
    case malformedData(details: String)
    /// Nessuna domanda trovata dove il template le prevede.
    case noQuestionsFound
}

/// I limiti del template Kahoot. Sono limiti *di Kahoot*: qui producono
/// avvisi informativi, mai scarti.
public enum KahootLimits {
    public static let questionMaxLength = 120
    public static let answerMaxLength = 75
    /// Prima riga di dati nel template ufficiale (le precedenti sono
    /// istruzioni e intestazioni).
    public static let firstDataRow = 9
}
