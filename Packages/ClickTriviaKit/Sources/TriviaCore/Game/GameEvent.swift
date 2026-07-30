import Foundation

/// Gli eventi di gioco che meritano un riscontro percepibile. Sono un
/// concetto di dominio: li emette il motore di partita; la traduzione sui
/// canali sensoriali (audio, aptico, visivo, annuncio VoiceOver) vive in
/// TriviaAccessibility. Ogni evento importante viaggia su più canali
/// insieme, mai sul solo colore: è il cuore della missione dell'app.
///
/// Il lessico segue il tema: il circuito che si chiude (risposta giusta)
/// o che resta interrotto (risposta sbagliata — un guizzo informativo,
/// mai una punizione).
public enum GameEvent: Hashable, Sendable {
    case matchStarted
    case questionPresented
    /// Risposta corretta: il circuito si chiude.
    case circuitClosed
    /// Risposta errata: il circuito resta interrotto.
    case circuitBroken
    /// La finestra del bonus inizia a salire.
    case bonusWindowOpened
    /// Il momento-bonus: da segnalare su tutti e tre i canali insieme.
    case bonusPeak
    case powerUpEarned
    case powerUpUsed
    case matchEnded
    /// Un giocatore è entrato nella sala (gioco in presenza).
    case peerJoined
    /// Un giocatore ha lasciato la sala.
    case peerLeft
    /// La connessione con la sala è andata persa.
    case connectionLost
}
