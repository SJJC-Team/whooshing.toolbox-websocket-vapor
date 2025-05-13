import NIOCore
import Logging
import WhooshingClient
import ErrorHandle

public protocol WSIOHandler: Sendable {
    func send(dataChunk: ByteBuffer, context: ChannelHandlerContext) -> EventLoopFuture<ByteBuffer>
    func get(dataChunk: ByteBuffer, context: ChannelHandlerContext) -> EventLoopFuture<ByteBuffer>
    func connectionStart(context: ChannelHandlerContext) -> EventLoopFuture<Void>
    func connectionEnd(context: ChannelHandlerContext) -> EventLoopFuture<Void>
}

public extension WSIOHandler {
    func connectionStart(context: ChannelHandlerContext) -> EventLoopFuture<Void> { context.eventLoop.makeSucceededVoidFuture() }
    func connectionEnd(context: ChannelHandlerContext) -> EventLoopFuture<Void> { context.eventLoop.makeSucceededVoidFuture() }
}

final class WSHandler: ChannelDuplexHandler, Sendable {
    typealias InboundIn = ByteBuffer
    typealias InboundOut = ByteBuffer
    typealias OutboundIn = ByteBuffer
    typealias OutboundOut = ByteBuffer
    
    private let logger: Logger?
    private let ioHandler: any WSIOHandler
    private unowned let tempPara: WebSocketClient.TempParas
    
    init(tempPara: WebSocketClient.TempParas, ioHandler: any WSIOHandler, logger: Logger? = nil) {
        self.logger = logger
        self.ioHandler = ioHandler
        self.tempPara = tempPara
    }
    
    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        var data = unwrapInboundIn(data)
        
        if data.readSlice(length: ChunkTool.eof.readableBytes) != ChunkTool.eof {
            data.moveReaderIndex(to: 0)
        }
        
        self.ioHandler.get(dataChunk: data, context: context).whenComplete { res in
            switch res {
            case .success(let data): context.fireChannelRead(self.wrapInboundOut(data))
            case .failure(let err): self.errorHappend(context: context, error: err)
            }
        }
    }
    
    func write(context: ChannelHandlerContext, data: NIOAny, promise: EventLoopPromise<Void>?) {
        let data = unwrapOutboundIn(data)
        guard data.readableBytes > 0 else { return }
        
        let r = self.ioHandler.send(dataChunk: data, context: context).flatMap { data in
            var buffer: ByteBuffer
            if self.tempPara.isUpgraded && self.tempPara.isLastUpgradeReqChunk {
                // Upgrade 请求的最后一个 Chunk
                buffer = ChunkTool.eof
                var d = data
                buffer.writeBuffer(&d)
            } else {
                buffer = data
            }
            return context.writeAndFlush(self.wrapOutboundOut(buffer))
        }.flatMapErrorThrowing { err in
            self.errorHappend(context: context, error: err)
        }
        
        if let p = promise {
            r.cascade(to: p)
        }
    }
    
    func channelRegistered(context: ChannelHandlerContext) {
        ioHandler.connectionStart(context: context).whenComplete { res in
            switch res {
            case .success(): self.tempPara.isUpgraded = false; self.tempPara.isLastUpgradeReqChunk = false
            case .failure(let err): self.errorHappend(context: context, error: err)
            }
        }
        context.fireChannelRegistered()
    }
    
    func channelUnregistered(context: ChannelHandlerContext) {
        ioHandler.connectionEnd(context: context).whenComplete { res in
            switch res {
            case .success(): self.tempPara.isUpgraded = false; self.tempPara.isLastUpgradeReqChunk = false
            case .failure(let err): self.errorHappend(context: context, error: err)
            }
        }
        context.fireChannelUnregistered()
    }
    
    func errorHappend(context: ChannelHandlerContext, error: any Error) {
        logger?.warning("\(error)")
        context.fireErrorCaught(error)
    }
    
}
