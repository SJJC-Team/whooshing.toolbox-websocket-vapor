import NIOCore
import WhooshingClient

public protocol WhooshingWebSocket: Sendable {
    /// 建立到指定 URL 的 WebSocket 连接。
    /// - Parameters:
    ///   - url: 目标 WebSocket 的 URL。
    ///   - headers: 连接时使用的 HTTP 头。
    ///   - eventLoop: 运行连接操作的事件循环。
    ///   - configuration: WebSocket 客户端配置。
    ///   - onUpgrade: 连接升级为 WebSocket 后调用的回调，传入已建立的 WebSocket 实例。
    /// - Returns: 一个表示连接操作完成的 `EventLoopFuture<Void>` 对象。
    @preconcurrency func connect(to url: WebURI, headers: HTTPHeaders, on eventLoop: any EventLoop, configuration: WebSocketClient.Configuration, onUpgrade: @Sendable @escaping (WebSocket) -> ()) -> EventLoopFuture<Void>
    
    /// 异步建立到指定 URL 的 WebSocket 连接。
    /// - Parameters:
    ///   - url: 目标 WebSocket 的 URL。
    ///   - headers: 连接时使用的 HTTP 头。
    ///   - configuration: WebSocket 客户端配置。
    ///   - onUpgrade: 连接升级为 WebSocket 后调用的回调，传入已建立的 WebSocket 实例。
    /// - Throws: 连接过程中可能抛出的错误。
    /// - Note: 该方法为异步版本，适用于支持 async/await 的上下文。
    @preconcurrency func connect(to url: WebURI, headers: HTTPHeaders, configuration: WebSocketClient.Configuration, onUpgrade: @Sendable @escaping (WebSocket) -> ()) async throws
}

public extension WhooshingWebSocket {
    /// 建立到指定 URL 的 WebSocket 连接，返回一个 `EventLoopFuture`。
    /// - Parameters:
    ///   - url: 目标 WebSocket 的 URL。
    ///   - headers: HTTP 请求头，默认空。
    ///   - eventLoop: 运行连接操作的事件循环。
    ///   - configuration: WebSocket 客户端配置，默认配置。
    ///   - onUpgrade: 连接成功升级为 WebSocket 时调用的回调。
    /// - Returns: 一个表示连接操作完成的 `EventLoopFuture<Void>` 对象。
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
}
