import Citadel
import Foundation
import NIOCore
import NIOPosix
import NIOSSH

struct PortForwardRule: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String
    var hostID: UUID
    var localPort: Int
    var targetHost: String
    var targetPort: Int
}

private final class TunnelRelayHandler: ChannelInboundHandler, RemovableChannelHandler {
    typealias InboundIn = ByteBuffer
    private let peer: Channel
    init(peer: Channel) { self.peer = peer }
    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        peer.writeAndFlush(unwrapInboundIn(data), promise: nil)
    }
    func channelInactive(context: ChannelHandlerContext) {
        peer.close(promise: nil)
        context.fireChannelInactive()
    }
    func errorCaught(context: ChannelHandlerContext, error: Error) {
        peer.close(promise: nil); context.close(promise: nil)
    }
}

actor PortForwardingService {
    static let shared = PortForwardingService()
    private let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
    private var listeners: [UUID: Channel] = [:]

    func start(rule: PortForwardRule, client: SSHClient) async throws {
        if listeners[rule.id] != nil { return }
        let bootstrap = ServerBootstrap(group: group)
            .serverChannelOption(ChannelOptions.backlog, value: 64)
            .serverChannelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)
            .childChannelOption(ChannelOptions.autoRead, value: false)
            .childChannelInitializer { inbound in
                let ready = inbound.eventLoop.makePromise(of: Void.self)
                Task {
                    do {
                        let origin: SocketAddress
                        if let remoteAddress = inbound.remoteAddress {
                            origin = remoteAddress
                        } else {
                            origin = try SocketAddress(ipAddress: "127.0.0.1", port: rule.localPort)
                        }
                        let remote = try await client.createDirectTCPIPChannel(
                            using: SSHChannelType.DirectTCPIP(
                                targetHost: rule.targetHost,
                                targetPort: rule.targetPort,
                                originatorAddress: origin
                            )
                        ) { remote in
                            remote.pipeline.addHandler(TunnelRelayHandler(peer: inbound))
                        }
                        try await inbound.pipeline.addHandler(TunnelRelayHandler(peer: remote)).get()
                        try await inbound.setOption(ChannelOptions.autoRead, value: true).get()
                        ready.succeed(())
                    } catch {
                        ready.fail(error)
                        inbound.close(promise: nil)
                    }
                }
                return ready.futureResult
            }
        listeners[rule.id] = try await bootstrap.bind(host: "127.0.0.1", port: rule.localPort).get()
    }

    func stop(ruleID: UUID) async {
        guard let listener = listeners.removeValue(forKey: ruleID) else { return }
        try? await listener.close().get()
    }
}

@MainActor
final class PortForwardingStore: ObservableObject {
    static let shared = PortForwardingStore()
    @Published private(set) var rules: [PortForwardRule] = []
    @Published private(set) var activeRuleIDs: Set<UUID> = []
    @Published var errorMessage: String?
    private let defaultsKey = "dev.termvault.portForwardRules"

    private init() {
        if let data = UserDefaults.standard.data(forKey: defaultsKey),
           let value = try? JSONDecoder().decode([PortForwardRule].self, from: data) { rules = value }
    }

    func save(_ rule: PortForwardRule) {
        if let index = rules.firstIndex(where: { $0.id == rule.id }) { rules[index] = rule }
        else { rules.append(rule) }
        persist()
    }

    func delete(_ rule: PortForwardRule) {
        Task { await PortForwardingService.shared.stop(ruleID: rule.id) }
        activeRuleIDs.remove(rule.id); rules.removeAll { $0.id == rule.id }; persist()
    }

    func toggle(_ rule: PortForwardRule, sessionStore: SessionStore) async {
        if activeRuleIDs.contains(rule.id) {
            await PortForwardingService.shared.stop(ruleID: rule.id)
            activeRuleIDs.remove(rule.id); return
        }
        guard let session = sessionStore.sessions.first(where: { $0.host.id == rule.hostID }),
              let client = await SSHSessionManager.shared.session(for: session.id) else {
            errorMessage = "Connect the selected host before starting its tunnel."; return
        }
        do {
            try await PortForwardingService.shared.start(rule: rule, client: client)
            activeRuleIDs.insert(rule.id)
        } catch { errorMessage = error.localizedDescription }
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(rules) { UserDefaults.standard.set(data, forKey: defaultsKey) }
    }
}
