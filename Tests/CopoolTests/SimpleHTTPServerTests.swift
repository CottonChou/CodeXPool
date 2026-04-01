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

    func testStreamingResponseUsesChunkedEncoding() async throws {
        let port: UInt16 = 19156
        let server = try SimpleHTTPServer(port: port) { _ in
            HTTPResponse.stream(
                statusCode: 200,
                headers: ["Content-Type": "text/event-stream; charset=utf-8"],
                chunks: [
                    Data("data: first\n\n".utf8),
                    Data("data: second\n\n".utf8)
                ]
            )
        }

        try await server.start()
        defer { server.stop() }

        let payload = try await rawHTTPResponse(
            port: port,
            request: "GET / HTTP/1.1\r\nHost: 127.0.0.1\r\n\r\n"
        )

        let text = String(decoding: payload, as: UTF8.self)
        XCTAssertTrue(text.contains("Transfer-Encoding: chunked"))
        XCTAssertTrue(text.contains("\r\n\r\ndata: first\n\n"))
        XCTAssertTrue(text.contains("\r\ndata: second\n\n\r\n0\r\n\r\n"))
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

private func rawHTTPResponse(port: UInt16, request: String) async throws -> Data {
    let connection = NWConnection(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: port)!, using: .tcp)
    let queue = DispatchQueue(label: "SimpleHTTPServerTests.Client")
    connection.start(queue: queue)
    defer { connection.cancel() }

    try await waitForReady(connection)
    try await sendRequest(connection, data: Data(request.utf8))

    var response = Data()
    while true {
        let chunk = try await receiveChunk(connection)
        if chunk.isEmpty { break }
        response.append(chunk)
    }

    return response
}

private func waitForReady(_ connection: NWConnection) async throws {
    try await withCheckedThrowingContinuation { continuation in
        let state = ConnectionResumeState()
        connection.stateUpdateHandler = { newState in
            switch state.consume(state: newState) {
            case .resume:
                continuation.resume()
            case .throwError(let error):
                continuation.resume(throwing: error)
            case .none:
                break
            }
        }
    }
}

private func sendRequest(_ connection: NWConnection, data: Data) async throws {
    try await withCheckedThrowingContinuation { continuation in
        connection.send(content: data, completion: .contentProcessed { error in
            if let error {
                continuation.resume(throwing: error)
            } else {
                continuation.resume()
            }
        })
    }
}

private func receiveChunk(_ connection: NWConnection) async throws -> Data {
    try await withCheckedThrowingContinuation { continuation in
        connection.receive(minimumIncompleteLength: 1, maximumLength: 4096) { data, _, isComplete, error in
            if let error {
                continuation.resume(throwing: error)
            } else {
                continuation.resume(returning: isComplete ? (data ?? Data()) : (data ?? Data()))
            }
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

private final class ConnectionResumeState: @unchecked Sendable {
    enum Action {
        case none
        case resume
        case throwError(Error)
    }

    private let lock = NSLock()
    private var hasResumed = false

    func consume(state: NWConnection.State) -> Action {
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
        case .cancelled:
            hasResumed = true
            return .throwError(XCTestError(.failureWhileWaiting))
        default:
            return .none
        }
    }
}
