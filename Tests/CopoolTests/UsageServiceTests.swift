import XCTest
@testable import Copool

final class UsageServiceTests: XCTestCase {
    override func tearDown() {
        super.tearDown()
        let resetExpectation = expectation(description: "reset usage mock url protocol")
        Task {
            await UsageMockURLProtocol.store.reset()
            resetExpectation.fulfill()
        }
        wait(for: [resetExpectation], timeout: 1)
    }

    func testFetchUsageShowsDirectServerErrorMessageForExpiredToken() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [UsageMockURLProtocol.self]
        let session = URLSession(configuration: configuration)
        let service = DefaultUsageService(
            session: session,
            configPath: URL(fileURLWithPath: "/tmp/nonexistent-config.toml")
        )

        await UsageMockURLProtocol.store.setHandler { request in
            let url = try XCTUnwrap(request.url?.absoluteString)
            if url.contains("/backend-api/wham/usage") {
                return (
                    HTTPURLResponse(
                        url: try XCTUnwrap(request.url),
                        statusCode: 401,
                        httpVersion: nil,
                        headerFields: nil
                    )!,
                    Data(#"{"error":{"message":"Provided authentication token is expired. Please try signing in again.","code":"token_expired"}}"#.utf8)
                )
            }

            return (
                HTTPURLResponse(
                    url: try XCTUnwrap(request.url),
                    statusCode: 403,
                    httpVersion: nil,
                    headerFields: nil
                )!,
                Data("<html>forbidden</html>".utf8)
            )
        }

        do {
            _ = try await service.fetchUsage(accessToken: "expired-token", accountID: "account-1")
            XCTFail("Expected usage request to fail")
        } catch {
            XCTAssertEqual(
                error.localizedDescription,
                "Provided authentication token is expired. Please try signing in again."
            )
        }
    }

    func testBackgroundNetworkSessionDisablesPersistentHTTPStorage() {
        let configuration = BackgroundNetworkSession.shared.configuration

        XCTAssertEqual(configuration.identifier, nil)
        XCTAssertEqual(configuration.requestCachePolicy, .reloadIgnoringLocalCacheData)
        XCTAssertNil(configuration.urlCache)
        XCTAssertNil(configuration.httpCookieStorage)
        XCTAssertFalse(configuration.httpShouldSetCookies)
    }
}

private final class UsageMockURLProtocol: URLProtocol, @unchecked Sendable {
    static let store = UsageMockURLProtocolStore()

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        Task {
            do {
                guard let handler = await Self.store.handler() else {
                    client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
                    return
                }

                let (response, data) = try handler(request)
                client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
                client?.urlProtocol(self, didLoad: data)
                client?.urlProtocolDidFinishLoading(self)
            } catch {
                client?.urlProtocol(self, didFailWithError: error)
            }
        }
    }

    override func stopLoading() {}
}

private actor UsageMockURLProtocolStore {
    typealias Handler = @Sendable (URLRequest) throws -> (HTTPURLResponse, Data)

    private var currentHandler: Handler?

    func setHandler(_ handler: @escaping Handler) {
        currentHandler = handler
    }

    func handler() -> Handler? {
        currentHandler
    }

    func reset() {
        currentHandler = nil
    }
}
