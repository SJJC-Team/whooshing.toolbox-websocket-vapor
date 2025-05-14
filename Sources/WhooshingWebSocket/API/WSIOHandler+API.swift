import NIOCore
import WhooshingClient
import Cryptos
import ErrorHandle
import NIOFoundationCompat
import Logging

#if WHOOSHING_VAPOR
import Vapor
#endif

enum API {
    struct WSIOCrypto: WSIOHandler, Sendable {
        
        let key: Crypto.Symm.Key
        let logger: Logger?
        
        /// 发送请求时，进行编码并加密
        func send(dataChunk: ByteBuffer, context: ChannelHandlerContext) -> EventLoopFuture<ByteBuffer> {
            context.eventLoop.submit {
                logger?.trace("API.WS.Client-发送数据中: 大小 \(ChunkTool.formatByteSize(dataChunk.readableBytes)) \(context.channel.clientAddrInfo)")
                do {
                    return try context.channel.allocator.buffer(data: Crypto.Symm.encrypt(dataChunk, key: key))
                } catch {
                    throw Err.responseEncryptFailed.d(14090, #file, #line).subErr(error)
                }
            }
        }
        
        /// 收到响应时，进行解密并解码
        func get(dataChunk: ByteBuffer, context: ChannelHandlerContext) -> EventLoopFuture<ByteBuffer> {
            context.eventLoop.submit {
                logger?.trace("API.WS.Client-接收数据中: 大小 \(ChunkTool.formatByteSize(dataChunk.readableBytes)) \(context.channel.clientAddrInfo)")
                do {
                    return try Crypto.Symm.decrypt(.init(buffer: dataChunk), key: key)
                } catch {
                    throw Err.responseEncryptFailed.d(14091, #file, #line).subErr(error)
                }
            }
        }
        
        func connectionStart(context: ChannelHandlerContext) -> EventLoopFuture<Void> {
            logger?.debug("API.WS.Client-连线建立: \(context.channel.clientAddrInfo)")
            return context.eventLoop.makeSucceededVoidFuture()
        }
        
        func connectionEnd(context: ChannelHandlerContext) -> EventLoopFuture<Void> {
            logger?.debug("API.WS.Client-连线结束: \(context.channel.clientAddrInfo)")
            return context.eventLoop.makeSucceededVoidFuture()
        }
        
        enum Err: String, ErrList {
            var domain: String { "woo.sys.websocket.crypto.err" }
            case responseEncryptFailed = "对响应加密时发生错误"
            case requestDecryptFailed = "对请求解密时发生错误"
        }
    }
}
