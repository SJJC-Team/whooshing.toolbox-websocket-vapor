import Foundation
import NIOCore
import NIOPosix
import NIOConcurrencyHelpers
import NIOExtras
import NIOHTTP1
import NIOWebSocket
import NIOSSL
import NIOTransportServices
import Atomics
import Logging

public final class WebSocketClient: Sendable {
    public enum Error: Swift.Error, LocalizedError {
        case invalidURL
        case invalidResponseStatus(HTTPResponseHead)
        case alreadyShutdown
        public var errorDescription: String? {
            return "\(self)"
        }
    }

    public typealias EventLoopGroupProvider = NIOEventLoopGroupProvider

    public struct Configuration: Sendable {
        public var tlsConfiguration: TLSConfiguration?
        public var maxFrameSize: Int

        /// Defends against small payloads in frame aggregation.
        /// See `NIOWebSocketFrameAggregator` for details.
        public var minNonFinalFragmentSize: Int
        /// Max number of fragments in an aggregated frame.
        /// See `NIOWebSocketFrameAggregator` for details.
        public var maxAccumulatedFrameCount: Int
        /// Maximum frame size after aggregation.
        /// See `NIOWebSocketFrameAggregator` for details.
        public var maxAccumulatedFrameSize: Int
        
        public var logger: Logger?
        
        public var ioHandler: (any WSIOHandler)?

        public init(
            ioHandler: (any WSIOHandler)? = nil,
            logger: Logger? = nil,
            tlsConfiguration: TLSConfiguration? = nil,
            maxFrameSize: Int = 1 << 14
        ) {
            self.ioHandler = ioHandler
            self.logger = logger
            self.tlsConfiguration = tlsConfiguration
            self.maxFrameSize = maxFrameSize
            self.minNonFinalFragmentSize = 0
            self.maxAccumulatedFrameCount = Int.max
            self.maxAccumulatedFrameSize = Int.max
        }
    }
    
    final class TempParas: @unchecked Sendable {
        private let lock = NIOLock()
        
        var isUpgraded: Bool {
            get { lock.withLock { __isUpgraded } }
            set { lock.withLock { __isUpgraded = newValue } }
        }
        private var __isUpgraded = false
        
        var isLastUpgradeReqChunk: Bool {
            get { lock.withLock { __isLastUpgradeReqChunk } }
            set { lock.withLock { __isLastUpgradeReqChunk = newValue } }
        }
        private var __isLastUpgradeReqChunk = false
    }

    let eventLoopGroupProvider: EventLoopGroupProvider
    let group: any EventLoopGroup
    let configuration: Configuration
    let isShutdown = ManagedAtomic(false)
    
    private let tempParas = TempParas()

    public init(eventLoopGroupProvider: EventLoopGroupProvider, configuration: Configuration = .init()) {
        self.eventLoopGroupProvider = eventLoopGroupProvider
        switch self.eventLoopGroupProvider {
        case .shared(let group):
            self.group = group
        case .createNew:
            self.group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        }
        self.configuration = configuration
    }

    @preconcurrency
    public func connect(
        scheme: String,
        host: String,
        port: Int,
        path: String = "/",
        query: String? = nil,
        headers: HTTPHeaders = [:],
        onUpgrade: @Sendable @escaping (WebSocket) -> ()
    ) -> EventLoopFuture<Void> {
        self.connect(scheme: scheme, host: host, port: port, path: path, query: query, headers: headers, proxy: nil, onUpgrade: onUpgrade)
    }

    /// Establish a WebSocket connection via a proxy server.
    ///
    /// - Parameters:
    ///   - scheme: Scheme component of the URI for the origin server.
    ///   - host: Host component of the URI for the origin server.
    ///   - port: Port on which to connect to the origin server.
    ///   - path: Path component of the URI for the origin server.
    ///   - query: Query component of the URI for the origin server.
    ///   - headers: Headers to send to the origin server.
    ///   - proxy: Host component of the URI for the proxy server.
    ///   - proxyPort: Port on which to connect to the proxy server.
    ///   - proxyHeaders: Headers to send to the proxy server.
    ///   - proxyConnectDeadline: Deadline for establishing the proxy connection.
    ///   - onUpgrade: An escaping closure to be executed after the upgrade is completed by `NIOWebSocketClientUpgrader`.
    /// - Returns: A future which completes when the connection to the origin server is established.
    @preconcurrency
    public func connect(
        scheme: String,
        host: String,
        port: Int,
        path: String = "/",
        query: String? = nil,
        headers: HTTPHeaders = [:],
        proxy: String?,
        proxyPort: Int? = nil,
        proxyHeaders: HTTPHeaders = [:],
        proxyConnectDeadline: NIODeadline = NIODeadline.distantFuture,
        onUpgrade: @Sendable @escaping (WebSocket) -> ()
    ) -> EventLoopFuture<Void> {
        assert(["ws", "wss"].contains(scheme))
        let upgradePromise = self.group.any().makePromise(of: Void.self)
        let bootstrap = WebSocketClient.makeBootstrap(on: self.group)
            .channelOption(ChannelOptions.socket(SocketOptionLevel(IPPROTO_TCP), TCP_NODELAY), value: 1)
            .channelInitializer { channel -> EventLoopFuture<Void> in
                let uri: String
                var upgradeRequestHeaders = headers
                if proxy == nil {
                    uri = path
                } else {
                    let relativePath = path.hasPrefix("/") ? path : "/" + path
                    let port = proxyPort.map { ":\($0)" } ?? ""
                    uri = "\(scheme)://\(host)\(relativePath)\(port)"

                    if scheme == "ws" {
                        upgradeRequestHeaders.add(contentsOf: proxyHeaders)
                    }
                }
                
                // 创建 WebSocketHandler，具体是否添加取决于 Configuration 中的 iohandler 是否不为 nil
                // 该 handler 为 Duplex 双向 Handler
                let wsHandler: WSHandler?
                
                if let ioHandler = self.configuration.ioHandler {
                    wsHandler = .init(tempPara: self.tempParas, ioHandler: ioHandler, logger: self.configuration.logger)
                } else {
                    wsHandler = nil
                }
                
                // 将 UpgradeHandler 的 HTTP 请求的 IOData 转为 ByteBuffer，方便后方的 WSHandler 处理
                // 该 Handler 为 OutBound Handler，只处理流出流量
                // 将会在成功 Upgraded 之后被移除，届时只剩下 WSHandler 处理 WebSocket Frame
                // 当然，如果 Configuration 中的 iohandler 为 nil，则上述都不会发生，该 WebSocket 将会照原来的 TLS 或明文传输
                let ioDataToBufferHandler = IODataToBufferHandler()
                
                let httpUpgradeRequestHandler = HTTPUpgradeRequestHandler(
                    host: host,
                    path: uri,
                    query: query,
                    headers: upgradeRequestHeaders,
                    upgradePromise: upgradePromise,
                    tempPara: self.tempParas
                )
                let httpUpgradeRequestHandlerBox = NIOLoopBound(httpUpgradeRequestHandler, eventLoop: channel.eventLoop)

                let websocketUpgrader = NIOWebSocketClientUpgrader(
                    maxFrameSize: self.configuration.maxFrameSize,
                    automaticErrorHandling: true,
                    upgradePipelineHandler: { channel, req in
                        if wsHandler != nil {
                            self.tempParas.isUpgraded = true
                        }
                        return WebSocket.client(on: channel, config: .init(clientConfig: self.configuration), onUpgrade: onUpgrade)
                    }
                )

                let config: NIOHTTPClientUpgradeConfiguration = (
                    upgraders: [websocketUpgrader],
                    completionHandler: { context in
                        upgradePromise.succeed(())
                        channel.pipeline.syncOperations.removeHandler(httpUpgradeRequestHandlerBox.value, promise: nil)
                        if wsHandler != nil {
                            // Upgraded 之后，移除用于将 Upgrade HTTP 请求从 IOData 转 ByteBuffer 的 Handler
                            // 因为接下来发送的不再是 HTTP 请求，而是 WebSocket Frame
                            channel.pipeline.syncOperations.removeHandler(ioDataToBufferHandler, promise: nil)
                        }
                    }
                )
                let configBox = NIOLoopBound(config, eventLoop: channel.eventLoop)

                if proxy == nil || scheme == "ws" {
                    if scheme == "wss" {
                        do {
                            let tlsHandler = try self.makeTLSHandler(tlsConfiguration: self.configuration.tlsConfiguration, host: host)
                            // The sync methods here are safe because we're on the channel event loop
                            // due to the promise originating on the event loop of the channel.
                            try channel.pipeline.syncOperations.addHandler(tlsHandler)
                        } catch {
                            return channel.pipeline.close(mode: .all)
                        }
                    }

                    return channel.eventLoop.submit {
                        if let wsh = wsHandler {
                            // 添加出入口粘包处理 Handler，并设置 WebSocket Handler
                            try channel.pipeline.syncOperations.addHandlers([
                                LengthFieldPrepender(lengthFieldLength: .eight, lengthFieldEndianness: .big),
                                ByteToMessageHandler(LengthFieldBasedFrameDecoder(lengthFieldLength: .eight, lengthFieldEndianness: .big)),
                                wsh,
                                ioDataToBufferHandler
                            ])
                        }
                        try channel.pipeline.syncOperations.addHTTPClientHandlers(
                            leftOverBytesStrategy: .forwardBytes,
                            withClientUpgrade: configBox.value
                        )
                        try channel.pipeline.syncOperations.addHandler(httpUpgradeRequestHandlerBox.value)
                    }
                }

                // TLS + proxy
                // we need to handle connecting with an additional CONNECT request
                let proxyEstablishedPromise = channel.eventLoop.makePromise(of: Void.self)
                let encoder = NIOLoopBound(HTTPRequestEncoder(), eventLoop: channel.eventLoop)
                let decoder = NIOLoopBound(ByteToMessageHandler(HTTPResponseDecoder(leftOverBytesStrategy: .dropBytes)), eventLoop: channel.eventLoop)

                var connectHeaders = proxyHeaders
                connectHeaders.add(name: "Host", value: host)

                let proxyRequestHandler = NIOHTTP1ProxyConnectHandler(
                    targetHost: host,
                    targetPort: port,
                    headers: connectHeaders,
                    deadline: proxyConnectDeadline,
                    promise: proxyEstablishedPromise
                )

                // This code block adds HTTP handlers to allow the proxy request handler to function.
                // They are then removed upon completion only to be re-added in `addHTTPClientHandlers`.
                // This is done because the HTTP decoder is not valid after an upgrade, the CONNECT request being counted as one.
                do {
                    try channel.pipeline.syncOperations.addHandler(encoder.value)
                    try channel.pipeline.syncOperations.addHandler(decoder.value)
                    try channel.pipeline.syncOperations.addHandler(proxyRequestHandler)
                } catch {
                    return channel.eventLoop.makeFailedFuture(error)
                }

                proxyEstablishedPromise.futureResult.flatMap {
                    channel.pipeline.syncOperations.removeHandler(decoder.value)
                }.flatMap {
                    channel.pipeline.syncOperations.removeHandler(encoder.value)
                }.whenComplete { result in
                    switch result {
                    case .success:
                        do {
                            let tlsHandler = try self.makeTLSHandler(tlsConfiguration: self.configuration.tlsConfiguration, host: host)
                            // The sync methods here are safe because we're on the channel event loop
                            // due to the promise originating on the event loop of the channel.
                            try channel.pipeline.syncOperations.addHandler(tlsHandler)
                            try channel.pipeline.syncOperations.addHTTPClientHandlers(
                                leftOverBytesStrategy: .forwardBytes,
                                withClientUpgrade: configBox.value
                            )
                            try channel.pipeline.syncOperations.addHandler(httpUpgradeRequestHandlerBox.value)
                        } catch {
                            channel.pipeline.close(mode: .all, promise: nil)
                        }
                    case .failure:
                        channel.pipeline.close(mode: .all, promise: nil)
                    }
                }

                return channel.eventLoop.makeSucceededVoidFuture()
            }

        let connect = bootstrap.connect(host: proxy ?? host, port: proxyPort ?? port)
        connect.cascadeFailure(to: upgradePromise)
        return connect.flatMap { channel in
            return upgradePromise.futureResult
        }
    }

    @Sendable
    private func makeTLSHandler(tlsConfiguration: TLSConfiguration?, host: String) throws -> NIOSSLClientHandler {
        let context = try NIOSSLContext(
            configuration: self.configuration.tlsConfiguration ?? .makeClientConfiguration()
        )
        let tlsHandler: NIOSSLClientHandler
        do {
            tlsHandler = try NIOSSLClientHandler(context: context, serverHostname: host)
        } catch let error as NIOSSLExtraError where error == .cannotUseIPAddressInSNI {
            tlsHandler = try NIOSSLClientHandler(context: context, serverHostname: nil)
        }
        return tlsHandler
    }

    public func syncShutdown() throws {
        switch self.eventLoopGroupProvider {
        case .shared:
            return
        case .createNew:
            if self.isShutdown.compareExchange(
                expected: false,
                desired: true,
                ordering: .relaxed
            ).exchanged {
                try self.group.syncShutdownGracefully()
            } else {
                throw WebSocketClient.Error.alreadyShutdown
            }
        }
    }
    
    private static func makeBootstrap(on eventLoop: any EventLoopGroup) -> any NIOClientTCPBootstrapProtocol {
        #if canImport(Network)
        if let tsBootstrap = NIOTSConnectionBootstrap(validatingGroup: eventLoop) {
            return tsBootstrap
        }
        #endif

        if let nioBootstrap = ClientBootstrap(validatingGroup: eventLoop) {
            return nioBootstrap
        }

        fatalError("No matching bootstrap found")
    }

    deinit {
        switch self.eventLoopGroupProvider {
        case .shared:
            return
        case .createNew:
            assert(self.isShutdown.load(ordering: .relaxed), "WebSocketClient not shutdown before deinit.")
        }
    }
}
