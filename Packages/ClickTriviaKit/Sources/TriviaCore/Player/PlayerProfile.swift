import Foundation

/// Il profilo di un giocatore. L'identità è **sempre locale**: `id` è un
/// identificatore interno stabile e mai mostrato all'utente. Il `nickname` è
/// solo un'etichetta leggibile: cambiarlo non tocca `id`, quindi punteggi,
/// storico e inventario (tutti agganciati all'`id`) restano intatti.
public struct PlayerProfile: Identifiable, Codable, Hashable, Sendable {
    public typealias ID = EntityID<PlayerProfile>

    /// Identificatore interno stabile. Non compare mai nell'interfaccia.
    public let id: ID

    /// Etichetta leggibile e liberamente modificabile.
    public var nickname: String

    public let createdAt: Date

    /// Aggancio a iCloud: opzionale, attivato dal giocatore, necessario solo
    /// per il gioco a distanza. L'app resta pienamente funzionante senza.
    public var cloudLink: CloudLinkState

    /// Inventario dei power-up guadagnati per merito.
    public var inventory: PowerUpInventory

    /// Preferenze personali (percezione del gioco): seguono il profilo,
    /// non la partita.
    public var preferences: PlayerPreferences

    /// Storico e avanzamento, agganciati all'`id` e non al nickname.
    public var progression: PlayerProgression

    public init(
        id: ID = ID(),
        nickname: String,
        createdAt: Date = Date(),
        cloudLink: CloudLinkState = .notLinked,
        inventory: PowerUpInventory = PowerUpInventory(),
        preferences: PlayerPreferences = .default,
        progression: PlayerProgression = .empty
    ) {
        self.id = id
        self.nickname = nickname
        self.createdAt = createdAt
        self.cloudLink = cloudLink
        self.inventory = inventory
        self.preferences = preferences
        self.progression = progression
    }
}

/// Stato dell'aggancio opzionale a iCloud. TriviaCore non importa CloudKit:
/// il record name è una stringa opaca, interpretata solo da TriviaRemote.
public enum CloudLinkState: Codable, Hashable, Sendable {
    case notLinked
    case linked(userRecordName: String)

    public var isLinked: Bool {
        if case .linked = self { return true }
        return false
    }
}
