import Foundation
import Combine

@MainActor
final class ClaudePageModel: ObservableObject {
    let coordinator: AccountsCoordinator

    private let noticeScheduler = NoticeAutoDismissScheduler()

    @Published var profiles: [ClaudeAPIKeyProfile] = []
    @Published var switchingProfileID: String?
    @Published var notice: NoticeMessage? {
        didSet {
            noticeScheduler.schedule(notice) { [weak self] in
                self?.notice = nil
            }
        }
    }

    var hasLoaded = false

    init(coordinator: AccountsCoordinator) {
        self.coordinator = coordinator
    }

    func loadIfNeeded() async {
        guard !hasLoaded else { return }
        hasLoaded = true
        await loadProfiles()
    }

    func loadProfiles() async {
        do {
            let profiles = try await coordinator.listClaudeAPIKeyProfiles()
            self.profiles = profiles
        } catch {
            notice = NoticeMessage(style: .error, text: error.localizedDescription)
        }
    }

    func saveProfile(_ profile: ClaudeAPIKeyProfile, isEditing: Bool) async {
        do {
            if isEditing {
                _ = try await coordinator.updateClaudeAPIKeyProfile(profile)
            } else {
                _ = try await coordinator.addClaudeAPIKeyProfile(profile)
            }
            await loadProfiles()
            notice = NoticeMessage(style: .success, text: L10n.tr("claude.notice.saved"))
        } catch {
            notice = NoticeMessage(style: .error, text: error.localizedDescription)
        }
    }

    func deleteProfile(id: String) async {
        do {
            try await coordinator.deleteClaudeAPIKeyProfile(id: id)
            await loadProfiles()
            notice = NoticeMessage(style: .success, text: L10n.tr("claude.notice.deleted"))
        } catch {
            notice = NoticeMessage(style: .error, text: error.localizedDescription)
        }
    }

    func switchToProfile(id: String) async {
        switchingProfileID = id
        do {
            try await coordinator.switchToClaudeAPIKeyProfile(id: id)
            await loadProfiles()
            notice = NoticeMessage(style: .success, text: L10n.tr("claude.notice.switched"))
        } catch {
            notice = NoticeMessage(style: .error, text: error.localizedDescription)
        }
        switchingProfileID = nil
    }
}
