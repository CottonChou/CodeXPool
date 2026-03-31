import XCTest
import Network
@testable import Copool

final class SimpleHTTPServerTests: XCTestCase {
    func testStartThrowsWhenPortAlreadyInUse() async throws {
        let occupiedPort: UInt16 = 19155
        let occupier = try PortOccupier(port: occupiedPort)
        try await occupier.start()

        let server = try SimpleHTTPServer(port: occupiedPort) { _ in
            HTTPResponse.text(statusCode: 200, text: "ok")
        }

        do {
            try await server.start()
            XCTFail("Expected start to fail when the port is already in use")
        } catch {
            XCTAssertFalse(error.localizedDescription.isEmpty)
        }
    }
}

private final class PortOccupier {
    private let listener: NWListener
    private let queue = DispatchQueue(label: "SimpleHTTPServerTests.PortOccupier")

    init(port: UInt16) throws {
        guard let nwPort = NWEndpoint.Port(rawValue: port) else {
            throw XCTSkip("Invalid test port")
        }
        listener = try NWListener(using: .tcp, on: nwPort)
    }

    deinit {
        listener.cancel()
    }

    func start() async throws {
        try await withCheckedThrowingContinuation { continuation in
            let resumeState = TestResumeState()
            listener.stateUpdateHandler = { state in
                switch resumeState.consume(state: state) {
                case .resume:
                    continuation.resume()
                case .throwError(let error):
                    continuation.resume(throwing: error)
                case .none:
                    break
                }
            }
            listener.start(queue: queue)
        }
    }
}

private final class TestResumeState: @unchecked Sendable {
    enum Action {
        case none
        case resume
        case throwError(Error)
    }

    private let lock = NSLock()
    private var hasResumed = false

    func consume(state: NWListener.State) -> Action {
        lock.lock()
        defer { lock.unlock() }

        guard !hasResumed else { return .none }

        switch state {
        case .ready:
            hasResumed = true
            return .resume
        case .failed(let error):
            hasResumed = true
            return .throwError(error)
        default:
            return .none
        }
    }
}
