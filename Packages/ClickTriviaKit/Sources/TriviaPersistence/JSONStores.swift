import Foundation
import TriviaCore

/// Persistenza di Fase 0: un file JSON per collezione, scritture atomiche,
/// tutto in Application Support. Offline-first per costruzione: questo store
/// funziona sempre, con o senza rete, con o senza iCloud. La sincronizzazione
/// CloudKit (Fase 4) sarà un livello *sopra*, mai un sostituto.

public enum PersistenceLocation {
    /// La cartella dati dell'app, creata al primo accesso.
    public static func dataDirectory() throws -> URL {
        let base = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let directory = base.appendingPathComponent("ClickTrivia", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}

/// Store generico: una collezione di elementi `Identifiable` in un singolo
/// file JSON. Actor: le scritture sono serializzate per costruzione.
public actor JSONCollectionStore<Item: Codable & Identifiable & Sendable>
where Item.ID: Hashable & Sendable {
    private let fileURL: URL
    private var cache: [Item]?

    public init(directory: URL, fileName: String) {
        self.fileURL = directory.appendingPathComponent(fileName)
    }

    public func loadAll() throws -> [Item] {
        if let cache { return cache }
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            cache = []
            return []
        }
        let data = try Data(contentsOf: fileURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let items = try decoder.decode([Item].self, from: data)
        cache = items
        return items
    }

    public func save(_ item: Item) throws {
        var items = try loadAll()
        if let index = items.firstIndex(where: { $0.id == item.id }) {
            items[index] = item
        } else {
            items.append(item)
        }
        try persist(items)
    }

    public func delete(_ id: Item.ID) throws {
        var items = try loadAll()
        items.removeAll { $0.id == id }
        try persist(items)
    }

    private func persist(_ items: [Item]) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(items)
        try data.write(to: fileURL, options: [.atomic])
        cache = items
    }
}

public struct JSONPlayerProfileStore: PlayerProfileStore {
    private let store: JSONCollectionStore<PlayerProfile>

    public init(directory: URL) {
        self.store = JSONCollectionStore(directory: directory, fileName: "players.json")
    }

    public func loadAll() async throws -> [PlayerProfile] { try await store.loadAll() }
    public func save(_ profile: PlayerProfile) async throws { try await store.save(profile) }
    public func delete(_ id: PlayerProfile.ID) async throws { try await store.delete(id) }
}

public struct JSONQuizStore: QuizStore {
    private let store: JSONCollectionStore<Quiz>

    public init(directory: URL) {
        self.store = JSONCollectionStore(directory: directory, fileName: "quizzes.json")
    }

    public func loadAll() async throws -> [Quiz] { try await store.loadAll() }
    public func save(_ quiz: Quiz) async throws { try await store.save(quiz) }
    public func delete(_ id: Quiz.ID) async throws { try await store.delete(id) }
}

public struct JSONGameSessionStore: GameSessionStore {
    private let store: JSONCollectionStore<GameSession>

    public init(directory: URL) {
        self.store = JSONCollectionStore(directory: directory, fileName: "sessions.json")
    }

    public func loadAll() async throws -> [GameSession] { try await store.loadAll() }
    public func save(_ session: GameSession) async throws { try await store.save(session) }
    public func delete(_ id: GameSession.ID) async throws { try await store.delete(id) }
}

/// Store in memoria: per anteprime SwiftUI, test e come rete di sicurezza
/// se il file system non fosse accessibile (l'app deve restare giocabile
/// in ogni circostanza).
public actor InMemoryStoreBox<Item: Codable & Identifiable & Sendable>
where Item.ID: Hashable & Sendable {
    private var items: [Item] = []

    public init(items: [Item] = []) {
        self.items = items
    }

    public func loadAll() -> [Item] { items }

    public func save(_ item: Item) {
        if let index = items.firstIndex(where: { $0.id == item.id }) {
            items[index] = item
        } else {
            items.append(item)
        }
    }

    public func delete(_ id: Item.ID) {
        items.removeAll { $0.id == id }
    }
}

public struct InMemoryPlayerProfileStore: PlayerProfileStore {
    private let box: InMemoryStoreBox<PlayerProfile>

    public init(profiles: [PlayerProfile] = []) {
        self.box = InMemoryStoreBox(items: profiles)
    }

    public func loadAll() async throws -> [PlayerProfile] { await box.loadAll() }
    public func save(_ profile: PlayerProfile) async throws { await box.save(profile) }
    public func delete(_ id: PlayerProfile.ID) async throws { await box.delete(id) }
}
