import WhooshingClient
import NIOCore
import Logging
import Cryptos

public final class APIWebSocket: WhooshingWebSocket, Sendable {
    
    public let logger: Logger?
    private let key: Crypto.Symm.Key
    
    public init(key: Crypto.Symm.Key, logger: Logger? = nil) {
        self.key = key
        self.logger = logger
    }
    
    public func configure(_ conf: inout WebSocketClient.Configuration) {
        conf.logger = self.logger
        conf.ioHandler = API.WSIOCrypto(key: key)
    }
}
