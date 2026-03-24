import Foundation

final class DefaultWorkspaceMetadataService: WorkspaceMetadataService, @unchecked Sendable {
    private enum RequestPolicy {
        static let timeout: TimeInterval = 5
        static let scope = "workspace-metadata"
    }

    private let session: URLSession
    private let configPath: URL
    private let endpointCoordinator: EndpointRequestCoordinator

    init(
        session: URLSession = BackgroundNetworkSession.shared,
        configPath: URL,
        endpointPreferenceStore: EndpointPreferenceStore = .shared
    ) {
        self.session = session
        self.configPath = configPath
        self.endpointCoordinator = EndpointRequestCoordinator(
            session: session,
            preferenceStore: endpointPreferenceStore
        )
    }

    func fetchWorkspaceMetadata(accessToken: String) async throws -> [WorkspaceMetadata] {
        do {
            let payload: WorkspaceAccountsResponse = try await endpointCoordinator.fetchFirstSuccessful(
                scope: RequestPolicy.scope,
                candidateURLs: resolveAccountURLs()
            ) { endpoint in
                var request = URLRequest(url: endpoint)
                request.timeoutInterval = RequestPolicy.timeout
                request.httpMethod = "GET"
                request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
                request.setValue("application/json", forHTTPHeaderField: "Accept")
                request.setValue("codex-tools-swift/0.1", forHTTPHeaderField: "User-Agent")
                return request
            } validate: { result in
                try JSONDecoder().decode(WorkspaceAccountsResponse.self, from: result.data)
            }
            let metadata = payload.items.map {
                WorkspaceMetadata(
                    accountID: $0.id,
                    workspaceName: $0.name,
                    structure: $0.structure
                )
            }
            return metadata
        } catch EndpointRequestError.allRequestsFailed(let errors) {
            if let message = Self.preferredUserFacingFailureMessage(from: errors) {
                throw AppError.network(message)
            }
            let preview = errors.prefix(2).joined(separator: " | ")
            if errors.count > 2 {
                throw AppError.network(L10n.tr("error.usage.request_failed_with_more_format", preview, String(errors.count - 2)))
            }
            throw AppError.network(L10n.tr("error.usage.request_failed_format", preview))
        }
    }

    private static func preferredUserFacingFailureMessage(from errors: [String]) -> String? {
        if errors.contains(where: isCancellationFailure) {
            return L10n.tr("error.workspace.discovery_cancelled")
        }
        if errors.contains(where: isTimeoutFailure) {
            return L10n.tr("error.workspace.discovery_timed_out")
        }
        if errors.contains(where: isHTMLForbiddenFailure) {
            return L10n.tr("error.workspace.discovery_forbidden")
        }

        for error in errors {
            let detail = error.components(separatedBy: ": ").dropFirst().joined(separator: ": ")
            guard let detail = detail.nonEmptyTrimmed, !detail.hasPrefix("<") else {
                continue
            }
            return detail
        }
        return nil
    }

    private static func isCancellationFailure(_ error: String) -> Bool {
        error.lowercased().contains("cancelled")
    }

    private static func isTimeoutFailure(_ error: String) -> Bool {
        let normalized = error.lowercased()
        return normalized.contains("timed out") || normalized.contains("timeout")
    }

    private static func isHTMLForbiddenFailure(_ error: String) -> Bool {
        let normalized = error.lowercased()
        let containsHTML = normalized.contains("<html") || normalized.contains("<head") || normalized.contains("<meta ")
        return containsHTML && normalized.contains("-> 403:")
    }

    private func resolveAccountURLs() -> [String] {
        let baseOrigin = ChatGPTBaseOriginResolver.resolve(configPath: configPath)
        let backendPrefix = "/backend-api"

        var candidates: [String] = []
        if let originWithoutBackend = baseOrigin.removingSuffix(backendPrefix) {
            candidates.append("\(baseOrigin)/accounts")
            candidates.append("\(originWithoutBackend)\(backendPrefix)/accounts")
        } else {
            candidates.append("\(baseOrigin)\(backendPrefix)/accounts")
        }

        candidates.append("https://chatgpt.com/backend-api/accounts")

        var deduped: [String] = []
        for candidate in candidates where !deduped.contains(candidate) {
            deduped.append(candidate)
        }
        return deduped
    }
}

private struct WorkspaceAccountsResponse: Decodable {
    var items: [WorkspaceAccountItem]
}

private struct WorkspaceAccountItem: Decodable {
    var id: String
    var name: String?
    var structure: String?
}

private extension String {
    func removingSuffix(_ suffix: String) -> String? {
        guard hasSuffix(suffix) else { return nil }
        return String(dropLast(suffix.count))
    }

    var nonEmptyTrimmed: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

#if DEBUG
extension DefaultWorkspaceMetadataService {
    static func debugPreferredUserFacingFailureMessage(from errors: [String]) -> String? {
        preferredUserFacingFailureMessage(from: errors)
    }
}
#endif
