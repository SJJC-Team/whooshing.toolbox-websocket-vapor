import NIOCore
import WhooshingClient
import ErrorHandle
import NIOHTTP1
import Logging
import Cryptos
import NIOExtras
import NIOWebSocket

#if WHOOSHING_VAPOR
import Vapor
#endif

/// 定义 WebSocket 客户端协议，支持异步与基于事件循环的连接方式。
///
/// 使用 `websocket.connect(to: onUpgrade:)` 建立新的 WebSocket 连线
/// `onUpgrade` 回调将会在 WebSocket 连线成功升级之后被调用
///
/// 下面使用该 API 实现一个简单的 WebSocket 连线，该连线将会在成功连线之后打印 "连线建立成功"
/// 之后发送 "Hello World!" 与对方
/// 若对方有消息发来，在 `onText` 中监听
///
/// ``` swift
/// let websocket = (初始化一个 WebSocket 实例，这取决于你使用哪个类型，例如 ApiWebSocket(...))
/// websocket.connect(to: "ws://localhost:8080/websocket") { ws in
///
///     print("WebSocket 建立连线成功")
///
///     ws.send("Hello World!")
///
///     ws.onText { ws, string in
///         print("收到了 String 消息: \(string)")
///     }
///
/// }
/// ```
///
/// 或是实现一个 echo WebSocket 连线
/// echo 连线是指将对方的消息以原样回复给对方
///
/// ``` swift
/// let websocket = ...
/// websocket.connect(to: "ws://localhost:8080/websocket") { ws in
///     ws.onText { ws, string in
///         // 收到消息后，简单地将其再次 send 回去
///         ws.send(string)
///     }
/// }
/// ```
///
/// 需要注意的是，`ws.send(...)` 函数的一次数据最大大小为 64kb，
/// 但由于 WebSocket 帧本身要占据部分字节，因此使用 `UInt16.max - 30` 作为最大大小进行判断最为合适
public protocol WhooshingWebSocket: AnyObject, Sendable {
    
    associatedtype Client: WhooshingClient
    
    /// 与 WebSocket 建立连接时所依赖的底层 HTTP 客户端。
    var client: Client { get }
    
    /// 可选日志记录器，用于记录连接过程中的调试信息。
    var logger: Logger? { get }
    
    /// 日志使用的标识前缀标签。
    static var loggerLabel: String { get }
    
    /// 建立到指定 URL 的 WebSocket 连接。
    /// - Parameters:
    ///   - url: WebSocket 的完整地址。
    ///   - headers: 可选 HTTP 请求头。
    ///   - eventLoop: 所属事件循环。
    ///   - configuration: WebSocket 配置项。
    ///   - onUpgrade: 成功建立连接时的回调，提供 WebSocket 对象。
    /// - Returns: 一个标识连接完成的 Future。
    @preconcurrency func connect(to url: WebURI, headers: HTTPHeaders, on eventLoop: any EventLoop, configuration: WebSocketClient.Configuration, onUpgrade: @Sendable @escaping (WebSocket) -> ()) -> EventLoopFuture<Void>
    
    /// 异步建立 WebSocket 连接。
    /// - Parameters:
    ///   - url: WebSocket 地址。
    ///   - headers: HTTP 请求头。
    ///   - configuration: WebSocket 配置。
    ///   - onUpgrade: 成功建立连接时的回调。
    /// - Throws: 请求过程中可能抛出的错误。
    @preconcurrency func connect(to url: WebURI, headers: HTTPHeaders, configuration: WebSocketClient.Configuration, onUpgrade: @Sendable @escaping (WebSocket) -> ()) async throws
}

/// 定义 WebSocket 相关的错误类型。
public enum WhooshingWebSocketErr: String, ErrList {
    public var domain: String { "woo.sys.api.websocket.err" }
    case responseError = "服务器返回的响应不正确"
    case unknowError = "发送请求时发生未知错误"
}

public extension WhooshingWebSocket {
    /// 提供基于事件循环的 `connect` 包装，兼容异步场景。
    /// 自动将异步连接过程封装进 `EventLoopFuture`。
    @preconcurrency
    func connect(
        to url: WebURI,
        headers: HTTPHeaders = [:],
        on eventLoop: any EventLoop,
        configuration: WebSocketClient.Configuration = .init(),
        onUpgrade: @Sendable @escaping (WebSocket) -> ()
    ) -> EventLoopFuture<Void> {
        eventLoop.makeFutureWithTask {
            try await self.connect(to: url, headers: headers, configuration: configuration, onUpgrade: onUpgrade)
        }
    }
    
    /// 完整异步连接流程，包括预检请求、升级协议、建立帧通道。
    /// - Parameters:
    ///   - url: WebSocket 地址。
    ///   - headers: 可选 HTTP 请求头。
    ///   - configuration: WebSocket 配置。
    ///   - onUpgrade: 成功建立连接时的回调。
    @preconcurrency
    func connect(
        to url: WebURI,
        headers: HTTPHeaders = [:],
        configuration: WebSocketClient.Configuration = .init(),
        onUpgrade: @Sendable @escaping (WebSocket) -> ()
    ) async throws {
        let httpURI = WebURI(scheme: .http, host: url.host, port: url.port, path: url.path, query: url.query, fragment: url.fragment)
        
        self.logger?.debug("\(Self.loggerLabel)-正在第一次 ping 以建立连接: \(httpURI)")
        try await self.firstPing(uri: httpURI)
        self.logger?.debug("\(Self.loggerLabel)-发送 WebSocket Upgrade 请求: \(httpURI)")
        try await self.upgradeReq(uri: httpURI, headers: headers)
        self.logger?.debug("\(Self.loggerLabel)-升级为 WebSocket 通道请求: \(url)")
        try await self.establishWebsocketConnect(configuration: configuration, onUpgrade: onUpgrade)
    }
}

extension WhooshingWebSocket {
    private func firstPing(uri: WebURI) async throws {
        let res = try await client.get(uri)
        guard res.status == .switchingProtocols else {
            throw WhooshingWebSocketErr.responseError.d("预期为 \(HTTPResponseStatus.switchingProtocols.code)(\(HTTPResponseStatus.switchingProtocols.reasonPhrase)), 却得到 \(res.status.code)(\(res.status.reasonPhrase))", 15001)
        }
    }
    
    private func upgradeReq(uri: WebURI, headers: HTTPHeaders) async throws {
        var headers = headers
        headers.replaceOrAdd(name: "upgrade", value: "websocket")
        headers.replaceOrAdd(name: "connection", value: "upgrade")
        headers.replaceOrAdd(name: "sec-websocket-key", value: Crypto.randomDataGenerate(length: 16).base64EncodedString())
        headers.replaceOrAdd(name: "sec-websocket-version", value: "13")

        let upgradeRes = try await client.get(uri, headers: headers)

        guard upgradeRes.status == .switchingProtocols else {
            throw WhooshingWebSocketErr.responseError.d("预期为 \(HTTPResponseStatus.switchingProtocols.code)(\(HTTPResponseStatus.switchingProtocols.reasonPhrase)), 却得到 \(upgradeRes.status.code)(\(upgradeRes.status.reasonPhrase))", 15001)
        }
    }

    private func establishWebsocketConnect(configuration: WebSocketClient.Configuration, onUpgrade: @Sendable @escaping (WebSocket) -> ()) async throws {
        guard
            let channel = client.channel,
            let mainHandler = client.mainHandler
        else {
            throw WhooshingWebSocketErr.unknowError.d("TCP 连接不存在，无法创建 WebSocket 连接", 15003)
        }

        guard let key = client.key else {
            throw WhooshingWebSocketErr.unknowError.d("密钥不存在", 15002)
        }

        let ioHandler = WSCryptoHandler(key: key, logger: logger)
        let wsHandler = WSHandler(ioHandler: ioHandler, logger: self.logger)
        
        self.logger?.trace("\(Self.loggerLabel)-在 TCP Channel 中建立 WebSocket Handler，并移除原有的 Client Handler")
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
}
