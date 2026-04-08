import Foundation
import CloudKit
#if os(macOS)
import Security
#endif

enum CloudKitSupport {
    static func makePrivateDatabase(containerIdentifier: String) -> CKDatabase? {
        guard hasCloudKitEntitlement() else {
            return nil
        }
        let container = CKContainer(identifier: containerIdentifier)
        return container.privateCloudDatabase
    }

    static func hasCloudKitEntitlement() -> Bool {
        #if os(macOS)
        guard let task = SecTaskCreateFromSelf(nil),
              let value = SecTaskCopyValueForEntitlement(
                task,
                "com.apple.developer.icloud-services" as CFString,
                nil
              ) else {
            return false
        }
        return containsCloudKitService(value)
        #else
        return true
        #endif
    }

    static func containsCloudKitService(_ value: Any) -> Bool {
        if let services = value as? [String] {
            return services.contains("CloudKit") || services.contains("CloudKit-Anonymous")
        }
        if let services = value as? NSArray {
            return services.contains { element in
                guard let service = element as? String else { return false }
                return service == "CloudKit" || service == "CloudKit-Anonymous"
            }
        }
        return false
    }
}

struct CloudSyncAvailabilityService {
    private let containerIdentifier = "iCloud.com.alick.copool"

    func isICloudAvailable() async -> Bool {
        guard CloudKitSupport.hasCloudKitEntitlement() else {
            return false
        }

        let container = CKContainer(identifier: containerIdentifier)
        return await withCheckedContinuation { continuation in
            container.accountStatus { status, _ in
                continuation.resume(returning: status == .available)
            }
        }
    }
}
