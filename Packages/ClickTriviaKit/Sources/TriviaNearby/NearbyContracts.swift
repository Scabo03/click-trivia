import Foundation
import TriviaCore

/// Fase 3 — Gioco in presenza via Multipeer Connectivity.
/// Modello: l'organizzatore apre la sala e detta il ritmo; chi si unisce
/// chiede di entrare e viene accettato esplicitamente. Le regole di
/// punteggio sono quelle comuni della partita; i tempi restano personali
/// (chi ha tempi estesi risponde col suo passo, l'host avanza quando il
/// gruppo è pronto — nessun timer rigido nemmeno qui).

public enum NearbyConstants {
    /// Limite pratico di Multipeer Connectivity: 8 dispositivi in tutto
    /// (1 organizzatore + 7 ospiti). Va comunicato chiaramente quando
    /// viene raggiunto: contatore in sala, annuncio all'host, messaggio
    /// esplicito al respinto.
    public static let maxPeersPerSession = 8

    /// Tipo di servizio Bonjour (≤ 15 caratteri, minuscole/cifre/trattini).
    public static let serviceType = "clicktrivia"
}

/// Un partecipante alla sala, identificato dal suo PlayerID stabile.
public struct NearbyParticipant: Codable, Hashable, Sendable, Identifiable {
    public let id: PlayerProfile.ID
    public var nickname: String
    public var isHost: Bool

    public init(id: PlayerProfile.ID, nickname: String, isHost: Bool) {
        self.id = id
        self.nickname = nickname
        self.isHost = isHost
    }
}

/// Lo stato della sala, condiviso con tutti a ogni variazione.
public struct RoomState: Codable, Hashable, Sendable {
    public var hostName: String
    public var quizTitle: String
    public var participants: [NearbyParticipant]
    public var capacity: Int

    public init(
        hostName: String,
        quizTitle: String,
        participants: [NearbyParticipant],
        capacity: Int = NearbyConstants.maxPeersPerSession
    ) {
        self.hostName = hostName
        self.quizTitle = quizTitle
        self.participants = participants
        self.capacity = capacity
    }

    public var isFull: Bool { participants.count >= capacity }
}

/// Il biglietto da visita di chi chiede di entrare (viaggia nel contesto
/// dell'invito Multipeer).
public struct JoinRequestPayload: Codable, Hashable, Sendable {
    public let playerID: PlayerProfile.ID
    public let nickname: String

    public init(playerID: PlayerProfile.ID, nickname: String) {
        self.playerID = playerID
        self.nickname = nickname
    }
}

/// La risposta di un giocatore, spedita all'organizzatore.
/// `elapsedFraction` è misurata sulla finestra personale del giocatore.
public struct AnswerPayload: Codable, Hashable, Sendable {
    public let playerID: PlayerProfile.ID
    public let questionIndex: Int
    public let selectedOptionID: AnswerOption.ID?
    public let elapsedFraction: Double?

    public init(
        playerID: PlayerProfile.ID,
        questionIndex: Int,
        selectedOptionID: AnswerOption.ID?,
        elapsedFraction: Double?
    ) {
        self.playerID = playerID
        self.questionIndex = questionIndex
        self.selectedOptionID = selectedOptionID
        self.elapsedFraction = elapsedFraction
    }
}

/// L'esito di un giocatore su un turno.
public struct RoundResultEntry: Codable, Hashable, Sendable, Identifiable {
    public let playerID: PlayerProfile.ID
    public let nickname: String
    public let isCorrect: Bool
    public let points: Int
    public let totalScore: Int
    public var id: PlayerProfile.ID { playerID }

    public init(
        playerID: PlayerProfile.ID,
        nickname: String,
        isCorrect: Bool,
        points: Int,
        totalScore: Int
    ) {
        self.playerID = playerID
        self.nickname = nickname
        self.isCorrect = isCorrect
        self.points = points
        self.totalScore = totalScore
    }
}

/// I risultati di un turno, calcolati dall'organizzatore con le regole
/// comuni e ridistribuiti a tutti.
public struct RoundResultsPayload: Codable, Hashable, Sendable {
    public let questionIndex: Int
    public let correctOptionID: AnswerOption.ID
    /// Ordinata per punteggio totale decrescente.
    public let entries: [RoundResultEntry]

    public init(questionIndex: Int, correctOptionID: AnswerOption.ID, entries: [RoundResultEntry]) {
        self.questionIndex = questionIndex
        self.correctOptionID = correctOptionID
        self.entries = entries
    }
}

/// Una posizione della classifica finale (ranking "1224": a pari punteggio,
/// pari posizione).
public struct FinalStanding: Codable, Hashable, Sendable, Identifiable {
    public let playerID: PlayerProfile.ID
    public let nickname: String
    public let totalScore: Int
    public let rank: Int
    public var id: PlayerProfile.ID { playerID }

    public init(playerID: PlayerProfile.ID, nickname: String, totalScore: Int, rank: Int) {
        self.playerID = playerID
        self.nickname = nickname
        self.totalScore = totalScore
        self.rank = rank
    }
}

public struct FinalResultsPayload: Codable, Hashable, Sendable {
    public let standings: [FinalStanding]

    public init(standings: [FinalStanding]) {
        self.standings = standings
    }
}

/// I messaggi della sala: brevi per contratto. L'unico payload sostanzioso
/// (il quiz) viaggia una volta sola, all'avvio della partita.
public enum NearbyMessage: Codable, Sendable {
    /// host → nuovo arrivato e a tutti: stato corrente della sala.
    case roomUpdated(RoomState)
    /// host → tutti: si comincia.
    case matchBegan(quiz: Quiz, configuration: MatchConfiguration)
    /// host → tutti: nuova domanda.
    case questionBegan(index: Int)
    /// ospite → host: la mia risposta.
    case answerSubmitted(AnswerPayload)
    /// host → tutti: quanti hanno risposto finora (stato di attesa leggibile).
    case answerProgress(answered: Int, total: Int)
    /// host → tutti: esiti del turno e punteggi aggiornati.
    case roundResults(RoundResultsPayload)
    /// host → tutti: classifica finale.
    case matchEnded(FinalResultsPayload)
    /// host → tutti: la sala chiude.
    case hostLeft
}
