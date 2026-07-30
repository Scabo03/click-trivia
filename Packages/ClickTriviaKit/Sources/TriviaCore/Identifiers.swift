import Foundation

/// Identificatore tipizzato tramite phantom type: `EntityID<PlayerProfile>` e
/// `EntityID<Question>` sono tipi distinti, quindi è impossibile passare l'ID
/// di un'entità dove ne serve un'altra.
///
/// Serializzato come singolo UUID, quindi stabile nel tempo e adatto sia al
/// salvataggio locale sia, in futuro, al mapping verso CloudKit.
public struct EntityID<Entity>: RawRepresentable, Hashable, Sendable {
    public let rawValue: UUID

    public init(rawValue: UUID) {
        self.rawValue = rawValue
    }

    /// Crea un nuovo identificatore casuale.
    public init() {
        self.rawValue = UUID()
    }
}

extension EntityID: Codable {
    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        self.rawValue = try container.decode(UUID.self)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

extension EntityID: CustomStringConvertible {
    public var description: String { rawValue.uuidString }
}
