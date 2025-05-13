import WhooshingClient
import NIOCore
import Logging
import Cryptos
import ErrorHandle
import NIOHTTP1

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
    public func beforeSend(to url: WebURI, conf: inout WebSocketClient.Configuration) async throws {
        let res = try await apiClient.get(url)
        guard res.status == .switchingProtocols else {
            throw Err.responseError.d("预期为 \(HTTPResponseStatus.switchingProtocols.code)(\(HTTPResponseStatus.switchingProtocols.reasonPhrase)), 却得到 \(res.status.code)(\(res.status.reasonPhrase)", 15001, (#file, #line))
        }
        guard let key = apiClient.key else {
            throw Err.unknowError.d("密钥不存在", 15002, (#file, #line))
        }
        conf.logger = self.logger
        conf.ioHandler = API.WSIOCrypto(key: key, logger: logger)
    }
    
    public enum Err: String, ErrList {
        public var domain: String { "woo.sys.api.websocket.err" }
        case responseError = "服务器返回的响应不正确"
        case unknowError = "发送请求时发生未知错误"
    }
}
