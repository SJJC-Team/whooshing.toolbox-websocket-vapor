import NIOCore

final class IODataToBufferHandler: RemovableChannelHandler, ChannelOutboundHandler, Sendable {
    typealias OutboundIn = IOData
    typealias OutboundOut = ByteBuffer
    
    func write(context: ChannelHandlerContext, data: NIOAny, promise: EventLoopPromise<Void>?) {
        let data = unwrapOutboundIn(data)
        guard case let .byteBuffer(data) = data else { return }
        context.writeAndFlush(self.wrapOutboundOut(data), promise: promise)
    }
}
