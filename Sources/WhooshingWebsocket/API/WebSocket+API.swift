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

/// APIWebSocket 是基于 Whooshing 协议的 WebSocket 客户端实现，
/// 提供连接建立、协议升级、安全通道初始化等功能，
/// 支持自定义事件循环和日志记录。
///
/// 该类封装了从 HTTP 到 WebSocket 的连接升级流程，
/// 包括首次 ping 测试连接、发送升级请求以及建立加密的 WebSocket 通道，
/// 方便用户通过异步接口安全地连接到指定的 WebSocket 服务。
public final class APIWebSocket: WhooshingWebSocket, Sendable {
    
    /// 可选的日志记录器，用于输出调试和运行时信息。
    public let logger: Logger?
    
    private let apiClient: ApiClient
    private let eventLoop: any EventLoop
    
    /// 使用指定的凭证和令牌初始化 APIWebSocket 实例。
    ///
    /// - Parameters:
    ///   - credential: 用于身份验证的凭证字符串。
    ///   - token: 用于身份验证的令牌字符串。
    ///   - eventLoop: 指定的事件循环，用于网络操作。
    ///   - logger: 可选的日志记录器，默认值为 nil。
    public init(credential: String, token: String, eventLoop: any EventLoop, logger: Logger? = nil) {
        self.logger = logger
        self.eventLoop = eventLoop
        self.apiClient = .init(credential: credential, token: token, eventLoop: eventLoop, logger: logger)
    }


    /// 异步建立到指定 URL 的 WebSocket 连接。
    ///
    /// 该方法会先通过 HTTP 协议发送一次 ping 请求以确保服务器连接可用，
    /// 然后发送 WebSocket 升级请求，最终完成 WebSocket 通道的建立。
    ///
    /// - Parameters:
    ///   - url: 目标 WebSocket 的 URI。
    ///   - headers: HTTP 请求头，默认值为空。
    ///   - configuration: WebSocket 客户端配置，默认使用默认配置。
    ///   - onUpgrade: 成功升级为 WebSocket 后调用的回调，提供已连接的 WebSocket。
    /// - Throws: 如果连接、握手或升级过程中出现任何错误，会抛出对应的异常。
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
    
    /// 定义 APIWebSocket 相关的错误类型。
    public enum Err: String, ErrList {
        public var domain: String { "woo.sys.api.websocket.err" }
        case responseError = "服务器返回的响应不正确"
        case unknowError = "发送请求时发生未知错误"
    }
}

extension WebSocketFrameEncoder: @unchecked @retroactive Sendable {}
