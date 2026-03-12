import Foundation
import Network

struct HTTPRequest {
    var method: String
    var path: String
    var headers: [String: String]
    var body: Data
}

struct HTTPResponse {
    var statusCode: Int
    var headers: [String: String]
    var body: Data

    static func json(statusCode: Int, object: Any) -> HTTPResponse {
        let data = (try? JSONSerialization.data(withJSONObject: object)) ?? Data("{}".utf8)
        return HTTPResponse(
            statusCode: statusCode,
            headers: ["Content-Type": "application/json; charset=utf-8"],
            body: data
        )
    }

    static func text(statusCode: Int, text: String) -> HTTPResponse {
        HTTPResponse(
            statusCode: statusCode,
            headers: ["Content-Type": "text/plain; charset=utf-8"],
            body: Data(text.utf8)
        )
    }
}

final class SimpleHTTPServer: @unchecked Sendable {
    typealias RequestHandler = @Sendable (HTTPRequest) async -> HTTPResponse

    private let listener: NWListener
    private let queue: DispatchQueue
    private let handler: RequestHandler

    init(port: UInt16, handler: @escaping RequestHandler) throws {
        guard let nwPort = NWEndpoint.Port(rawValue: port) else {
            throw AppError.invalidData(L10n.tr("error.http_server.invalid_port_format", String(port)))
        }
        self.listener = try NWListener(using: .tcp, on: nwPort)
        self.queue = DispatchQueue(label: "codex.tools.swift.proxy.listener", qos: .userInitiated)
        self.handler = handler
    }

    func start() {
        listener.newConnectionHandler = { [weak self] connection in
            self?.handle(connection: connection)
        }
        listener.start(queue: queue)
    }

    func stop() {
        listener.cancel()
    }

    private func handle(connection: NWConnection) {
        connection.start(queue: queue)
        readRequest(on: connection, buffer: Data())
    }

    private func readRequest(on connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, isComplete, error in
            guard let self else {
                connection.cancel()
                return
            }

            if let error {
                connection.cancel()
                NSLog("SimpleHTTPServer receive error: \(error.localizedDescription)")
                return
            }

            var working = buffer
            if let data, !data.isEmpty {
                working.append(data)
            }

            if let request = Self.parseRequest(from: working) {
                Task {
                    let response = await self.handler(request)
                    self.send(response: response, on: connection)
                }
                return
            }

            if isComplete {
                let response = HTTPResponse.text(statusCode: 400, text: "Bad Request")
                send(response: response, on: connection)
                return
            }

            self.readRequest(on: connection, buffer: working)
        }
    }

    private func send(response: HTTPResponse, on connection: NWConnection) {
        let payload = Self.encode(response: response)
        connection.send(content: payload, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    private static func parseRequest(from data: Data) -> HTTPRequest? {
        guard let headerRange = data.range(of: Data("\r\n\r\n".utf8)) else {
            return nil
        }

        let headerData = data.subdata(in: 0..<headerRange.lowerBound)
        guard let headerText = String(data: headerData, encoding: .utf8) else {
            return nil
        }

        let lines = headerText.split(separator: "\r\n", omittingEmptySubsequences: false)
        guard let requestLine = lines.first else {
            return nil
        }

        let requestParts = requestLine.split(separator: " ")
        guard requestParts.count >= 2 else {
            return nil
        }

        let method = String(requestParts[0]).uppercased()
        let path = String(requestParts[1]).split(separator: "?").first.map(String.init) ?? "/"

        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            guard let index = line.firstIndex(of: ":") else { continue }
            let name = line[..<index].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let value = line[line.index(after: index)...].trimmingCharacters(in: .whitespacesAndNewlines)
            headers[name] = value
        }

        let contentLength = Int(headers["content-length"] ?? "0") ?? 0
        let bodyStart = headerRange.upperBound
        let expectedEnd = bodyStart + contentLength
        guard data.count >= expectedEnd else {
            return nil
        }

        let body = contentLength == 0 ? Data() : data.subdata(in: bodyStart..<expectedEnd)
        return HTTPRequest(method: method, path: path, headers: headers, body: body)
    }

    private static func encode(response: HTTPResponse) -> Data {
        let reason = reasonPhrase(for: response.statusCode)
        var headerLines: [String] = [
            "HTTP/1.1 \(response.statusCode) \(reason)",
            "Connection: close",
            "Content-Length: \(response.body.count)"
        ]

        for (key, value) in response.headers {
            headerLines.append("\(key): \(value)")
        }
        headerLines.append("\r\n")

        var output = Data(headerLines.joined(separator: "\r\n").utf8)
        output.append(response.body)
        return output
    }

    private static func reasonPhrase(for statusCode: Int) -> String {
        switch statusCode {
        case 200: return "OK"
        case 400: return "Bad Request"
        case 401: return "Unauthorized"
        case 404: return "Not Found"
        case 429: return "Too Many Requests"
        case 500: return "Internal Server Error"
        case 502: return "Bad Gateway"
        default: return "HTTP"
        }
    }
}
