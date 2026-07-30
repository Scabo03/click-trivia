import Foundation
import MultipeerConnectivity
import OSLog
import TriviaCore

/// Il trasporto Multipeer, incapsulato: sessione, advertising (host) e
/// browsing (ospite). Le callback dei delegate arrivano su code arbitrarie
/// e vengono ricondotte al MainActor; il resto dell'app vede solo closure
/// tipizzate e messaggi `NearbyMessage`.
///
/// La capienza è applicata qui: a sala piena le richieste vengono rifiutate
/// automaticamente e la cosa viene riferita all'host (che la annuncia),
/// mai inghiottita in silenzio.
@MainActor
public final class MultipeerTransport: NSObject {

    public struct DiscoveredRoom: Identifiable, Hashable {
        public let id: String
        public let hostName: String
        let peer: MCPeerID
    }

    public struct PendingJoinRequest: Identifiable {
        public let id: UUID
        public let payload: JoinRequestPayload
        let peer: MCPeerID
        let handler: (Bool, MCSession?) -> Void
    }

    // MARK: - Callback verso il controller

    public var onRoomsChanged: (([DiscoveredRoom]) -> Void)?
    public var onPendingRequestsChanged: (([PendingJoinRequest]) -> Void)?
    public var onGuestConnected: ((JoinRequestPayload) -> Void)?
    public var onGuestDisconnected: ((JoinRequestPayload) -> Void)?
    public var onConnectedToHost: (() -> Void)?
    public var onDisconnectedFromHost: (() -> Void)?
    public var onMessage: ((NearbyMessage) -> Void)?
    /// Richiesta rifiutata in automatico perché la sala è piena (nickname).
    public var onRoomFullAutoDecline: ((String) -> Void)?

    // MARK: - Stato interno

    private var myPeerID: MCPeerID?
    private var session: MCSession?
    private var advertiser: MCNearbyServiceAdvertiser?
    private var browser: MCNearbyServiceBrowser?
    private var hostPeer: MCPeerID?
    private var isHosting = false

    private var discoveredRooms: [DiscoveredRoom] = []
    private var pendingRequests: [PendingJoinRequest] = []
    /// peer approvati → identità dichiarata alla richiesta.
    private var approvedProfiles: [MCPeerID: JoinRequestPayload] = [:]

    private var myPayload: JoinRequestPayload?
    private let logger = Logger(subsystem: "ClickTrivia", category: "nearby")

    // MARK: - Avvio e chiusura

    public func startHosting(as payload: JoinRequestPayload) {
        stop()
        isHosting = true
        myPayload = payload
        let peer = makePeerID(nickname: payload.nickname)
        myPeerID = peer
        let session = makeSession(peer: peer)
        self.session = session

        let advertiser = MCNearbyServiceAdvertiser(
            peer: peer,
            discoveryInfo: nil,
            serviceType: NearbyConstants.serviceType
        )
        advertiser.delegate = self
        advertiser.startAdvertisingPeer()
        self.advertiser = advertiser
    }

    public func startBrowsing(as payload: JoinRequestPayload) {
        stop()
        isHosting = false
        myPayload = payload
        let peer = makePeerID(nickname: payload.nickname)
        myPeerID = peer
        session = makeSession(peer: peer)

        let browser = MCNearbyServiceBrowser(peer: peer, serviceType: NearbyConstants.serviceType)
        browser.delegate = self
        browser.startBrowsingForPeers()
        self.browser = browser
    }

    public func requestJoin(_ room: DiscoveredRoom) {
        guard let browser, let session, let myPayload else { return }
        hostPeer = room.peer
        let context = try? JSONEncoder().encode(myPayload)
        browser.invitePeer(room.peer, to: session, withContext: context, timeout: 30)
    }

    /// L'organizzatore accetta o rifiuta esplicitamente una richiesta.
    public func respond(to request: PendingJoinRequest, accept: Bool) {
        pendingRequests.removeAll { $0.id == request.id }
        onPendingRequestsChanged?(pendingRequests)

        if accept {
            guard let session, currentOccupancy < NearbyConstants.maxPeersPerSession else {
                request.handler(false, nil)
                onRoomFullAutoDecline?(request.payload.nickname)
                return
            }
            approvedProfiles[request.peer] = request.payload
            request.handler(true, session)
        } else {
            request.handler(false, nil)
        }
    }

    public func send(_ message: NearbyMessage) {
        guard let session, !session.connectedPeers.isEmpty else { return }
        do {
            let data = try JSONEncoder().encode(message)
            try session.send(data, toPeers: session.connectedPeers, with: .reliable)
        } catch {
            logger.error("Invio messaggio fallito: \(error.localizedDescription)")
        }
    }

    public func stop() {
        advertiser?.stopAdvertisingPeer()
        advertiser = nil
        browser?.stopBrowsingForPeers()
        browser = nil
        session?.disconnect()
        session = nil
        hostPeer = nil
        discoveredRooms = []
        for request in pendingRequests {
            request.handler(false, nil)
        }
        pendingRequests = []
        approvedProfiles = [:]
    }

    // MARK: - Supporto

    /// Occupazione corrente: ospiti connessi + l'organizzatore.
    private var currentOccupancy: Int {
        (session?.connectedPeers.count ?? 0) + 1
    }

    private func makePeerID(nickname: String) -> MCPeerID {
        let trimmed = nickname.trimmingCharacters(in: .whitespacesAndNewlines)
        let display = trimmed.isEmpty ? "ClickTrivia" : String(trimmed.prefix(40))
        return MCPeerID(displayName: display)
    }

    private func makeSession(peer: MCPeerID) -> MCSession {
        let session = MCSession(
            peer: peer,
            securityIdentity: nil,
            encryptionPreference: .required
        )
        session.delegate = self
        return session
    }

    // MARK: - Gestione eventi (già sul MainActor)

    fileprivate func handlePeerStateChange(_ peer: MCPeerID, state: MCSessionState) {
        if isHosting {
            switch state {
            case .connected:
                if let payload = approvedProfiles[peer] {
                    onGuestConnected?(payload)
                }
            case .notConnected:
                if let payload = approvedProfiles.removeValue(forKey: peer) {
                    onGuestDisconnected?(payload)
                }
            default:
                break
            }
        } else if peer == hostPeer {
            switch state {
            case .connected:
                onConnectedToHost?()
            case .notConnected:
                onDisconnectedFromHost?()
            default:
                break
            }
        }
    }

    fileprivate func handleReceivedData(_ data: Data) {
        do {
            let message = try JSONDecoder().decode(NearbyMessage.self, from: data)
            onMessage?(message)
        } catch {
            logger.error("Messaggio non decodificabile: \(error.localizedDescription)")
        }
    }

    fileprivate func handleInvitation(
        from peer: MCPeerID,
        context: Data?,
        handler: @escaping (Bool, MCSession?) -> Void
    ) {
        let payload: JoinRequestPayload
        if let context,
           let decoded = try? JSONDecoder().decode(JoinRequestPayload.self, from: context) {
            payload = decoded
        } else {
            payload = JoinRequestPayload(playerID: PlayerProfile.ID(), nickname: peer.displayName)
        }

        // Sala piena (contando anche le richieste in attesa di decisione):
        // rifiuto automatico, riferito all'host perché lo annunci.
        guard currentOccupancy + pendingRequests.count < NearbyConstants.maxPeersPerSession else {
            handler(false, nil)
            onRoomFullAutoDecline?(payload.nickname)
            return
        }

        pendingRequests.append(PendingJoinRequest(
            id: UUID(),
            payload: payload,
            peer: peer,
            handler: handler
        ))
        onPendingRequestsChanged?(pendingRequests)
    }

    fileprivate func handleFoundPeer(_ peer: MCPeerID) {
        let room = DiscoveredRoom(
            id: peer.displayName + String(peer.hash),
            hostName: peer.displayName,
            peer: peer
        )
        if !discoveredRooms.contains(where: { $0.peer == peer }) {
            discoveredRooms.append(room)
            onRoomsChanged?(discoveredRooms)
        }
    }

    fileprivate func handleLostPeer(_ peer: MCPeerID) {
        discoveredRooms.removeAll { $0.peer == peer }
        onRoomsChanged?(discoveredRooms)
    }
}

// MARK: - Ponti dai delegate (code arbitrarie) al MainActor

/// MCPeerID e l'invitation handler non sono Sendable ma sono thread-safe
/// nell'uso che ne facciamo (valori immutabili passati una sola volta):
/// le scatole li traghettano nel salto verso il MainActor.
private struct PeerBox: @unchecked Sendable {
    let peer: MCPeerID
}

private struct InvitationBox: @unchecked Sendable {
    let handler: (Bool, MCSession?) -> Void
}

extension MultipeerTransport: MCSessionDelegate {
    public nonisolated func session(
        _ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState
    ) {
        let box = PeerBox(peer: peerID)
        Task { @MainActor in
            self.handlePeerStateChange(box.peer, state: state)
        }
    }

    public nonisolated func session(
        _ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID
    ) {
        Task { @MainActor in
            self.handleReceivedData(data)
        }
    }

    public nonisolated func session(
        _ session: MCSession, didReceive stream: InputStream,
        withName streamName: String, fromPeer peerID: MCPeerID
    ) {}

    public nonisolated func session(
        _ session: MCSession, didStartReceivingResourceWithName resourceName: String,
        fromPeer peerID: MCPeerID, with progress: Progress
    ) {}

    public nonisolated func session(
        _ session: MCSession, didFinishReceivingResourceWithName resourceName: String,
        fromPeer peerID: MCPeerID, at localURL: URL?, withError error: (any Error)?
    ) {}
}

extension MultipeerTransport: MCNearbyServiceAdvertiserDelegate {
    public nonisolated func advertiser(
        _ advertiser: MCNearbyServiceAdvertiser,
        didReceiveInvitationFromPeer peerID: MCPeerID,
        withContext context: Data?,
        invitationHandler: @escaping (Bool, MCSession?) -> Void
    ) {
        let peerBox = PeerBox(peer: peerID)
        let handlerBox = InvitationBox(handler: invitationHandler)
        Task { @MainActor in
            self.handleInvitation(from: peerBox.peer, context: context, handler: handlerBox.handler)
        }
    }
}

extension MultipeerTransport: MCNearbyServiceBrowserDelegate {
    public nonisolated func browser(
        _ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID,
        withDiscoveryInfo info: [String: String]?
    ) {
        let box = PeerBox(peer: peerID)
        Task { @MainActor in
            self.handleFoundPeer(box.peer)
        }
    }

    public nonisolated func browser(
        _ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID
    ) {
        let box = PeerBox(peer: peerID)
        Task { @MainActor in
            self.handleLostPeer(box.peer)
        }
    }
}
