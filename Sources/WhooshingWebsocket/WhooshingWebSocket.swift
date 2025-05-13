import NIOCore
import WhooshingClient

public protocol WhooshingWebSocket: Sendable {
    @preconcurrency func connect(to url: WebURI, headers: HTTPHeaders, configuration: WebSocketClient.Configuration, on eventLoop: any EventLoop, onUpgrade: @Sendable @escaping (WebSocket) -> ()) -> EventLoopFuture<Void>
    @preconcurrency func connect(host: String, port: Int, path: String, query: String?, headers: HTTPHeaders, configuration: WebSocketClient.Configuration, on eventLoop: any EventLoop, onUpgrade: @Sendable @escaping (WebSocket) -> ()) -> EventLoopFuture<Void>
    @preconcurrency func connect(host: String, port: Int, path: String, query: String?, headers: HTTPHeaders, proxy: String?, proxyPort: Int?, proxyHeaders: HTTPHeaders, proxyConnectDeadline: NIODeadline, configuration: WebSocketClient.Configuration, on eventLoop: any EventLoop, onUpgrade: @Sendable @escaping (WebSocket) -> ()) -> EventLoopFuture<Void>
    @preconcurrency func connect(to url: WebURI, headers: HTTPHeaders, proxy: String?, proxyPort: Int?, proxyHeaders: HTTPHeaders, proxyConnectDeadline: NIODeadline, configuration: WebSocketClient.Configuration, on eventLoop: any EventLoop, onUpgrade: @Sendable @escaping (WebSocket) -> ()) -> EventLoopFuture<Void>
    
    @preconcurrency func beforeSend(to url: WebURI, conf: inout WebSocketClient.Configuration) async throws
}

public extension WhooshingWebSocket {
    @preconcurrency
    func connect(
        host: String,
        port: Int = 80,
        path: String = "/",
        query: String? = nil,
        headers: HTTPHeaders = [:],
        configuration: WebSocketClient.Configuration = .init(),
        on eventLoop: any EventLoop,
        onUpgrade: @Sendable @escaping (WebSocket) -> ()
    ) -> EventLoopFuture<Void> {
        self.connect(to: .init(scheme: .ws, host: host, port: port, path: path, query: query), headers: headers, configuration: configuration, on: eventLoop, onUpgrade: onUpgrade)
    }
    
    @preconcurrency
    func connect(
        host: String,
        port: Int = 80,
        path: String = "/",
        query: String? = nil,
        headers: HTTPHeaders = [:],
        proxy: String?,
        proxyPort: Int? = nil,
        proxyHeaders: HTTPHeaders = [:],
        proxyConnectDeadline: NIODeadline = NIODeadline.distantFuture,
        configuration: WebSocketClient.Configuration = .init(),
        on eventLoop: any EventLoop,
        onUpgrade: @Sendable @escaping (WebSocket) -> ()
    ) -> EventLoopFuture<Void> {
        self.connect(to: .init(scheme: .ws, host: host, port: port, path: path, query: query), headers: headers, proxy: proxy, proxyPort: proxyPort, proxyHeaders: proxyHeaders, proxyConnectDeadline: proxyConnectDeadline, configuration: configuration, on: eventLoop, onUpgrade: onUpgrade)
    }
    
    @preconcurrency
    func connect(
        to url: WebURI,
        headers: HTTPHeaders = [:],
        configuration: WebSocketClient.Configuration = .init(),
        on eventLoop: any EventLoop,
        onUpgrade: @Sendable @escaping (WebSocket) -> ()
    ) -> EventLoopFuture<Void> {
        self.connect(to: url, headers: headers, configuration: configuration, on: eventLoop, onUpgrade: onUpgrade)
    }
    
    @preconcurrency
    func connect(
        to url: WebURI,
        headers: HTTPHeaders = [:],
        proxy: String?,
        proxyPort: Int? = nil,
        proxyHeaders: HTTPHeaders = [:],
        proxyConnectDeadline: NIODeadline = NIODeadline.distantFuture,
        configuration: WebSocketClient.Configuration = .init(),
        on eventLoop: any EventLoop,
        onUpgrade: @Sendable @escaping (WebSocket) -> ()
    ) -> EventLoopFuture<Void> {
        eventLoop.makeFutureWithTask {
            var conf = configuration
            try await self.beforeSend(to: url, conf: &conf)
            return conf
        }.flatMap { conf in
            WebSocket.connect(to: url.string, headers: headers, proxy: proxy, proxyPort: proxyPort, proxyHeaders: proxyHeaders, proxyConnectDeadline: proxyConnectDeadline, configuration: conf, on: eventLoop, onUpgrade: onUpgrade)
        }
    }
}
