import WhooshingClient
import NIOCore
import Logging
import Cryptos
import ErrorHandle
import NIOHTTP1
import NIOWebSocket

#if WHOOSHING_VAPOR
import Vapor
#endif

public final class APIWebSocket: WhooshingWebSocket, Sendable {
    
    public let logger: Logger?
    private let apiClient: ApiClient
    private let eventLoop: any EventLoop
    
    public init(credential: String, token: String, eventLoop: any EventLoop, logger: Logger? = nil) {
        self.logger = logger
        self.eventLoop = eventLoop
        self.apiClient = .init(credential: credential, token: token, eventLoop: eventLoop, logger: logger)
    }


    @preconcurrency
    public func connect(
        to url: WebURI,
        headers: HTTPHeaders = [:],
        configuration: WebSocketClient.Configuration = .init(),
        onUpgrade: @Sendable @escaping (WebSocket) -> ()
    ) async throws {
        let httpURI = WebURI(scheme: .http, host: url.host, port: url.port, path: url.path, query: url.query, fragment: url.fragment)
        
        self.logger?.debug("API.WS.Client-正在第一次 ping 以建立连接: \(httpURI)")
        try await self.firstPing(uri: httpURI)
        self.logger?.debug("API.WS.Client-发送 WebSocket Upgrade 请求: \(httpURI)")
        try await self.upgradeReq(uri: httpURI, headers: headers)
        self.logger?.debug("API.WS.Client-升级为 WebSocket 通道请求: \(url)")
        try await self.establishWebsocketConnect(configuration: configuration, onUpgrade: onUpgrade)
    }

    private func firstPing(uri: WebURI) async throws {
        let res = try await apiClient.get(uri)
        guard res.status == .switchingProtocols else {
            throw Err.responseError.d("预期为 \(HTTPResponseStatus.switchingProtocols.code)(\(HTTPResponseStatus.switchingProtocols.reasonPhrase)), 却得到 \(res.status.code)(\(res.status.reasonPhrase))", 15001, (#file, #line))
        }
    }

    // GET /chat HTTP/1.1
    // Host: example.com:80
    // Upgrade: websocket
    // Connection: Upgrade
    // Sec-WebSocket-Key: x3JJHMbDL1EzLkh9GBhXDw==
    // Sec-WebSocket-Version: 13
    private func upgradeReq(uri: WebURI, headers: HTTPHeaders) async throws {
        var headers = headers
        headers.replaceOrAdd(name: "upgrade", value: "websocket")
        headers.replaceOrAdd(name: "connection", value: "upgrade")
        headers.replaceOrAdd(name: "sec-websocket-key", value: Crypto.randomDataGenerate(length: 16).base64EncodedString())
        headers.replaceOrAdd(name: "sec-websocket-version", value: "13")

        let upgradeRes = try await apiClient.get(uri, headers: headers)

        guard upgradeRes.status == .switchingProtocols else {
            throw Err.responseError.d("预期为 \(HTTPResponseStatus.switchingProtocols.code)(\(HTTPResponseStatus.switchingProtocols.reasonPhrase)), 却得到 \(upgradeRes.status.code)(\(upgradeRes.status.reasonPhrase))", 15001, (#file, #line))
        }
    }

    private func establishWebsocketConnect(configuration: WebSocketClient.Configuration, onUpgrade: @Sendable @escaping (WebSocket) -> ()) async throws {
        guard
            let channel = apiClient.channel,
            let mainHandler = apiClient.mainHandler
        else {
            throw Err.unknowError.d("TCP 连接不存在，无法创建 WebSocket 连接", 15003, (#file, #line))
        }

        guard let key = apiClient.key else {
            throw Err.unknowError.d("密钥不存在", 15002, (#file, #line))
        }

        let ioHandler = API.WSIOCrypto(key: key, logger: logger)
        let wsHandler = WSHandler(ioHandler: ioHandler, logger: self.logger)
        
        self.logger?.trace("API.WS.Client-在 TCP Channel 中建立 WebSocket Handler，并移除原有的 API Handler")
        try await channel.pipeline.removeHandler(mainHandler)
        try await channel.pipeline.addHandlers([
            wsHandler,
            WebSocketFrameEncoder(),
            ByteToMessageHandler(WebSocketFrameDecoder(maxFrameSize: ChunkTool.maxChunk))
        ])

        channel.eventLoop.flatSubmit {
            WebSocket.client(on: channel, config: .init(clientConfig: configuration), onUpgrade: onUpgrade)
        }.whenFailure { err in
            self.logger?.warning("\(err)")
            channel.close(promise: nil)
        }
    }
    
    public enum Err: String, ErrList {
        public var domain: String { "woo.sys.api.websocket.err" }
        case responseError = "服务器返回的响应不正确"
        case unknowError = "发送请求时发生未知错误"
    }
}

extension WebSocketFrameEncoder: @unchecked @retroactive Sendable {}
