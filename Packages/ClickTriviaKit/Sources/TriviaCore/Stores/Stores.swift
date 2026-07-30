import Foundation

/// Contratti di persistenza del dominio. TriviaCore definisce *cosa* serve
/// salvare; *come* lo decide chi implementa (TriviaPersistence su file JSON
/// in Fase 0, TriviaRemote per la sincronizzazione CloudKit in Fase 4).
/// È il punto di estensione che garantisce l'offline-first: il dominio non
/// sa se sotto c'è un file locale o iCloud.

public protocol PlayerProfileStore: Sendable {
    func loadAll() async throws -> [PlayerProfile]
    func save(_ profile: PlayerProfile) async throws
    func delete(_ id: PlayerProfile.ID) async throws
}

public protocol QuizStore: Sendable {
    func loadAll() async throws -> [Quiz]
    func save(_ quiz: Quiz) async throws
    func delete(_ id: Quiz.ID) async throws
}

public protocol GameSessionStore: Sendable {
    func loadAll() async throws -> [GameSession]
    func save(_ session: GameSession) async throws
    func delete(_ id: GameSession.ID) async throws
}
