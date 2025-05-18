import WhooshingClient
import Logging

#if WHOOSHING_VAPOR
import Vapor
#endif

/// 基于 WhooshingClient 实现的 API 模块 WebSocket 客户端封装，
/// 提供通用的 WebSocket 连接支持
///
/// 另见 ``WhooshingWebSocket`` 协议
public final class ApiWebSocket: WhooshingWebSocket, Sendable {
    
    /// 日志标识标签，用于跟踪日志输出来源。
    public static let loggerLabel = "API.WS.Client"
    
    /// 日志记录器，用于输出调试与运行信息。
    public let logger: Logger?
    
    /// 所使用的底层 HTTP 客户端实例。
    public let client: ApiClient
    
    /// 当前所使用的事件循环实例。
    private let eventLoop: any EventLoop
    
    /// 使用凭证和 token 初始化 WebSocket 客户端。
    /// - Parameters:
    ///   - credential: 客户端身份凭证。
    ///   - token: 用于认证的访问令牌。
    ///   - eventLoop: 所使用的事件循环。
    ///   - logger: 可选日志记录器。
    public init(credential: String, token: String, eventLoop: any EventLoop, logger: Logger? = nil) {
        self.logger = logger
        self.eventLoop = eventLoop
        self.client = .init(credential: credential, token: token, eventLoop: eventLoop, logger: logger)
    }
    
    /// 使用已有的 ApiClient 实例初始化 WebSocket 客户端。
    /// - Parameter client: 已构造的 API 客户端。
    public init(client: ApiClient) {
        self.client = client
        self.logger = client.logger
        self.eventLoop = client.eventLoop
    }
    
    #if WHOOSHING_VAPOR
    /// Vapor 环境下的初始化方式。
    /// 自动从 Application 获取 eventLoop 和 logger。
    /// - Parameters:
    ///   - credential: 身份凭证。
    ///   - token: 授权令牌。
    ///   - app: Vapor 应用上下文。
    public init(credential: String, token: String, app: Application) {
        self.logger = app.logger
        self.eventLoop = app.eventLoopGroup.next()
        self.client = .init(credential: credential, token: token, eventLoop: eventLoop, logger: logger)
    }
    #endif
}
