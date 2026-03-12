import Foundation

struct SystemDateProvider: DateProviding {
    func unixSecondsNow() -> Int64 {
        Int64(Date().timeIntervalSince1970)
    }
}
