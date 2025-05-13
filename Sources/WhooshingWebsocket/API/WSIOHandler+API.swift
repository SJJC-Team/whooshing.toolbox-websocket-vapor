import NIOCore
import WhooshingClient
import Cryptos
import ErrorHandle
import NIOFoundationCompat

enum API {
    
    struct WSIOCrypto: WSIOHandler, Sendable {
        
        let key: Crypto.Symm.Key
        
        /// 发送请求时，进行编码并加密
        func send(dataChunk: ByteBuffer, context: ChannelHandlerContext) -> EventLoopFuture<ByteBuffer> {
            context.eventLoop.submit {
                do {
                    return try Crypto.Symm.decrypt(.init(buffer: dataChunk), key: key)
                } catch {
                    throw Err.responseEncryptFailed.d(14090, #file, #line).subErr(error)
                }
            }
        }
        
        /// 收到响应时，进行解密并解码
        func get(dataChunk: ByteBuffer, context: ChannelHandlerContext) -> EventLoopFuture<ByteBuffer> {
            context.eventLoop.submit {
                do {
                    return try context.channel.allocator.buffer(data: Crypto.Symm.encrypt(dataChunk, key: key))
                } catch {
                    throw Err.responseEncryptFailed.d(14091, #file, #line).subErr(error)
                }
            }
        }
        
        enum Err: String, ErrList {
            var domain: String { "woo.sys.websocket.crypto.err" }
            case responseEncryptFailed = "对响应加密时发生错误"
            case requestDecryptFailed = "对请求解密时发生错误"
        }
    }
}
