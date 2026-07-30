import Foundation

/// I tipi di power-up. Sono meccanica di gioco: vivono nel profilo del
/// giocatore e agiscono sullo stato della partita, mai sulla domanda.
public enum PowerUpKind: Codable, Hashable, Sendable {
    /// Nasconde `count` risposte sbagliate, riducendo la scelta.
    /// `count` diversi sono power-up **distinti** nell'inventario: possono
    /// avere costi e frequenze di guadagno diversi.
    case hideIncorrectAnswers(count: Int)

    /// L'aiuto leggero e comune ("Fusibile"): con 4 opzioni ne restano 3.
    public static let lightHideOne = PowerUpKind.hideIncorrectAnswers(count: 1)

    /// Il classico fifty-fifty ("Corto circuito"), più potente e più raro:
    /// con 4 opzioni restano la corretta e una sbagliata.
    public static let classicHideTwo = PowerUpKind.hideIncorrectAnswers(count: 2)

    /// Nome tecnico stabile, utile per log e telemetria locale.
    public var identifier: String {
        switch self {
        case .hideIncorrectAnswers(let count): "hideIncorrectAnswers(\(count))"
        }
    }
}

/// L'inventario di power-up di un giocatore. Predisposto fin dall'inizio,
/// anche se parte vuoto: si riempie solo per merito.
public struct PowerUpInventory: Codable, Hashable, Sendable {
    public enum InventoryError: Error, Equatable, Sendable {
        case notAvailable(PowerUpKind)
    }

    private var counts: [PowerUpKind: Int]

    public init() {
        self.counts = [:]
    }

    public func count(of kind: PowerUpKind) -> Int {
        counts[kind, default: 0]
    }

    public var isEmpty: Bool {
        counts.values.allSatisfy { $0 <= 0 }
    }

    /// Tutti i power-up posseduti, con la relativa quantità, in ordine stabile.
    public var owned: [OwnedPowerUp] {
        counts
            .filter { $0.value > 0 }
            .map { OwnedPowerUp(kind: $0.key, count: $0.value) }
            .sorted { $0.id < $1.id }
    }

    public mutating func add(_ kind: PowerUpKind, count: Int = 1) {
        guard count > 0 else { return }
        counts[kind, default: 0] += count
    }

    /// Consuma un power-up; lancia se non disponibile.
    public mutating func use(_ kind: PowerUpKind) throws {
        guard count(of: kind) > 0 else {
            throw InventoryError.notAvailable(kind)
        }
        counts[kind]? -= 1
        if counts[kind] == 0 {
            counts.removeValue(forKey: kind)
        }
    }
}

/// Una voce dell'inventario: power-up posseduto e quantità.
public struct OwnedPowerUp: Identifiable, Hashable, Sendable {
    public let kind: PowerUpKind
    public let count: Int
    public var id: String { kind.identifier }
}

/// Rarità: governa (in futuro) costi e frequenza di guadagno.
public enum PowerUpRarity: String, Codable, CaseIterable, Sendable {
    case common
    case rare
}

/// Scheda descrittiva di un power-up: nome a tema, spiegazione, rarità.
/// È presentazione + bilanciamento, separata dalla meccanica (`PowerUpKind`).
public struct PowerUpDescriptor: Identifiable, Sendable {
    public var id: String { kind.identifier }
    public let kind: PowerUpKind
    public let name: String
    public let detail: String
    public let rarity: PowerUpRarity

    public init(kind: PowerUpKind, name: String, detail: String, rarity: PowerUpRarity) {
        self.kind = kind
        self.name = name
        self.detail = detail
        self.rarity = rarity
    }
}

/// Il catalogo dei power-up dell'app.
public enum PowerUpCatalog {
    public static let standard: [PowerUpDescriptor] = [
        PowerUpDescriptor(
            kind: .lightHideOne,
            name: String(localized: "Fusibile"),
            detail: String(localized: "Brucia una risposta sbagliata: ne restano tre."),
            rarity: .common
        ),
        PowerUpDescriptor(
            kind: .classicHideTwo,
            name: String(localized: "Corto circuito"),
            detail: String(localized: "Brucia due risposte sbagliate: ne restano due."),
            rarity: .rare
        ),
    ]

    public static func descriptor(for kind: PowerUpKind) -> PowerUpDescriptor? {
        standard.first { $0.kind == kind }
    }
}

/// Un power-up guadagnato: cosa, quando e perché (sempre per merito).
public struct PowerUpAward: Codable, Hashable, Sendable {
    public enum Reason: Codable, Hashable, Sendable {
        /// N risposte corrette consecutive.
        case correctStreak(length: Int)
        /// Quiz completato senza errori.
        case perfectQuiz(quizID: Quiz.ID)
        /// Estensione futura: motivazioni definite dalle regole di lega.
        case custom(String)
    }

    public var kind: PowerUpKind
    public var reason: Reason
    public var date: Date

    public init(kind: PowerUpKind, reason: Reason, date: Date) {
        self.kind = kind
        self.reason = reason
        self.date = date
    }
}
