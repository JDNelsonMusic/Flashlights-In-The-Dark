import OSCKit

public extension OscBroadcaster {
    @inline(__always)
    func send<T: OscCodable>(_ model: T) async throws {
        try await send(model.encode())
    }
}