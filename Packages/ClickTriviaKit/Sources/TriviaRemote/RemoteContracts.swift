import Foundation
import TriviaCore

/// Fase 4 — Gioco a distanza asincrono via CloudKit. Per ora solo i
/// contratti. Principio architetturale: CloudKit è un livello di
/// sincronizzazione *sopra* la persistenza locale, mai un requisito.
/// Tutto ciò che passa da qui deve degradare con grazia.

/// Disponibilità del servizio remoto: ogni caso ha una risposta di prodotto
/// (mai un vicolo cieco), perché l'app resta pienamente giocabile in locale.
public enum CloudAvailability: Equatable, Sendable {
    case available
    /// Nessun account iCloud: l'online semplicemente non compare tra le
    /// opzioni, con una spiegazione chiara e non colpevolizzante.
    case noAccount
    /// Restrizioni (parental control, profili gestiti).
    case restricted
    /// Quota iCloud piena: si continua a giocare, la sincronizzazione riprende
    /// quando possibile.
    case quotaExceeded
    case networkUnavailable
}

/// Il servizio remoto, astratto da CloudKit. Il mapping verso CKRecord
/// vivrà interamente in questo modulo.
public protocol RemoteSyncService: Sendable {
    func availability() async -> CloudAvailability

    /// Aggancio opzionale del profilo a iCloud, attivato dal giocatore.
    /// Restituisce l'identificatore opaco da conservare in `CloudLinkState`.
    func linkCurrentAccount() async throws -> String
}
