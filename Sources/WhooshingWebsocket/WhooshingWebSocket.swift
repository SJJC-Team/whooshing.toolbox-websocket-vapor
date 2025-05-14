import NIOCore
import WhooshingClient

public protocol WhooshingWebSocket: Sendable {
    @preconcurrency func connect(to url: WebURI, headers: HTTPHeaders, on eventLoop: any EventLoop, configuration: WebSocketClient.Configuration, onUpgrade: @Sendable @escaping (WebSocket) -> ()) -> EventLoopFuture<Void>
    @preconcurrency func connect(host: String, port: Int, path: String, query: String?, headers: HTTPHeaders, on eventLoop: any EventLoop, configuration: WebSocketClient.Configuration, onUpgrade: @Sendable @escaping (WebSocket) -> ()) -> EventLoopFuture<Void>
    @preconcurrency func connect(host: String, port: Int, path: String, query: String?, headers: HTTPHeaders, configuration: WebSocketClient.Configuration, onUpgrade: @Sendable @escaping (WebSocket) -> ()) async throws

    @preconcurrency func connect(to url: WebURI, headers: HTTPHeaders, configuration: WebSocketClient.Configuration, onUpgrade: @Sendable @escaping (WebSocket) -> ()) async throws
}

public extension WhooshingWebSocket {
    @preconcurrency
    func connect(
        host: String,
        port: Int = 80,
        path: String = "/",
        query: String? = nil,
        headers: HTTPHeaders = [:],
        on eventLoop: any EventLoop,
        configuration: WebSocketClient.Configuration = .init(),
        onUpgrade: @Sendable @escaping (WebSocket) -> ()
    ) -> EventLoopFuture<Void> {
        eventLoop.makeFutureWithTask {
            try await self.connect(host: host, port: port, path: path, query: query, headers: headers, configuration: configuration, onUpgrade: onUpgrade)
        }
    }

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

    @preconcurrency
    func connect(
        host: String,
        port: Int = 80,
        path: String = "/",
        query: String? = nil,
        headers: HTTPHeaders = [:],
        configuration: WebSocketClient.Configuration = .init(),
        onUpgrade: @Sendable @escaping (WebSocket) -> ()
    ) async throws {
        try await self.connect(to: .init(scheme: .ws, host: host, port: port, path: path, query: query), headers: headers, configuration: configuration, onUpgrade: onUpgrade)
    }
}
