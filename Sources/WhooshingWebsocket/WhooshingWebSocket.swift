import NIOCore

public protocol WhooshingWebSocket: Sendable {
    @preconcurrency func connect(to url: String, headers: HTTPHeaders, configuration: WebSocketClient.Configuration, on eventLoopGroup: any EventLoopGroup, onUpgrade: @Sendable @escaping (WebSocket) -> ()) -> EventLoopFuture<Void>
    @preconcurrency func connect(to url: URL, headers: HTTPHeaders, configuration: WebSocketClient.Configuration, on eventLoopGroup: any EventLoopGroup, onUpgrade: @Sendable @escaping (WebSocket) -> ()) -> EventLoopFuture<Void>
    @preconcurrency func connect(scheme: String, host: String, port: Int, path: String, query: String?, headers: HTTPHeaders, configuration: WebSocketClient.Configuration, on eventLoopGroup: any EventLoopGroup, onUpgrade: @Sendable @escaping (WebSocket) -> ()) -> EventLoopFuture<Void>
    @preconcurrency func connect(scheme: String, host: String, port: Int, path: String, query: String?, headers: HTTPHeaders, proxy: String?, proxyPort: Int?, proxyHeaders: HTTPHeaders, proxyConnectDeadline: NIODeadline, configuration: WebSocketClient.Configuration, on eventLoopGroup: any EventLoopGroup, onUpgrade: @Sendable @escaping (WebSocket) -> ()) -> EventLoopFuture<Void>
    @preconcurrency func connect(to url: String, headers: HTTPHeaders, proxy: String?, proxyPort: Int?, proxyHeaders: HTTPHeaders, proxyConnectDeadline: NIODeadline, configuration: WebSocketClient.Configuration, on eventLoopGroup: any EventLoopGroup, onUpgrade: @Sendable @escaping (WebSocket) -> ()) -> EventLoopFuture<Void>
    
    @preconcurrency func configure(_ conf: inout WebSocketClient.Configuration)
}

public extension WhooshingWebSocket {
    @preconcurrency
    func connect(
        to url: String,
        headers: HTTPHeaders = [:],
        configuration: WebSocketClient.Configuration = .init(),
        on eventLoopGroup: any EventLoopGroup,
        onUpgrade: @Sendable @escaping (WebSocket) -> ()
    ) -> EventLoopFuture<Void> {
        var conf = configuration
        self.configure(&conf)
        return WebSocket.connect(to: url, headers: headers, configuration: conf, on: eventLoopGroup, onUpgrade: onUpgrade)
    }
    
    @preconcurrency
    func connect(
        to url: URL,
        headers: HTTPHeaders = [:],
        configuration: WebSocketClient.Configuration = .init(),
        on eventLoopGroup: any EventLoopGroup,
        onUpgrade: @Sendable @escaping (WebSocket) -> ()
    ) -> EventLoopFuture<Void> {
        var conf = configuration
        self.configure(&conf)
        return WebSocket.connect(to: url, headers: headers, configuration: conf, on: eventLoopGroup, onUpgrade: onUpgrade)
    }
    
    @preconcurrency
    func connect(
        scheme: String = "ws",
        host: String,
        port: Int = 80,
        path: String = "/",
        query: String? = nil,
        headers: HTTPHeaders = [:],
        configuration: WebSocketClient.Configuration = .init(),
        on eventLoopGroup: any EventLoopGroup,
        onUpgrade: @Sendable @escaping (WebSocket) -> ()
    ) -> EventLoopFuture<Void> {
        var conf = configuration
        self.configure(&conf)
        return WebSocket.connect(scheme: scheme, host: host, port: port, path: path, query: query, headers: headers, configuration: conf, on: eventLoopGroup, onUpgrade: onUpgrade)
    }
    
    @preconcurrency
    func connect(
        scheme: String = "ws",
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
        on eventLoopGroup: any EventLoopGroup,
        onUpgrade: @Sendable @escaping (WebSocket) -> ()
    ) -> EventLoopFuture<Void> {
        var conf = configuration
        self.configure(&conf)
        return WebSocket.connect(scheme: scheme, host: host, port: port, path: path, query: query, headers: headers, proxy: proxy, proxyPort: proxyPort, proxyHeaders: proxyHeaders, proxyConnectDeadline: proxyConnectDeadline, configuration: conf, on: eventLoopGroup, onUpgrade: onUpgrade)
    }
    
    @preconcurrency
    func connect(
        to url: String,
        headers: HTTPHeaders = [:],
        proxy: String?,
        proxyPort: Int? = nil,
        proxyHeaders: HTTPHeaders = [:],
        proxyConnectDeadline: NIODeadline = NIODeadline.distantFuture,
        configuration: WebSocketClient.Configuration = .init(),
        on eventLoopGroup: any EventLoopGroup,
        onUpgrade: @Sendable @escaping (WebSocket) -> ()
    ) -> EventLoopFuture<Void> {
        var conf = configuration
        self.configure(&conf)
        return WebSocket.connect(to: url, headers: headers, proxy: proxy, proxyPort: proxyPort, proxyHeaders: proxyHeaders, proxyConnectDeadline: proxyConnectDeadline, configuration: conf, on: eventLoopGroup, onUpgrade: onUpgrade)
    }
}
