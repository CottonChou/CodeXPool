import XCTest
@testable import Copool

final class RemoteProxydBinaryBuilderTests: XCTestCase {
    func testPrepareBinaryPathForBuildRemovesExistingCachedBinaryWhenForceRebuildEnabled() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let builder = RemoteProxydBinaryBuilder(
            repoRoot: nil,
            fileManager: .default,
            commandRunner: RemoteShellCommandRunner(fileManager: .default)
        )
        let binaryPath = tempDir.appendingPathComponent("codex-tools-proxyd", isDirectory: false)
        try writeExecutableStub(to: binaryPath)

        let shouldReuse = try builder.prepareBinaryPathForBuild(binaryPath, forceRebuild: true)

        XCTAssertFalse(shouldReuse)
        XCTAssertFalse(FileManager.default.fileExists(atPath: binaryPath.path))
    }

    func testPrepareBinaryPathForBuildKeepsExistingCachedBinaryWhenForceRebuildDisabled() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let builder = RemoteProxydBinaryBuilder(
            repoRoot: nil,
            fileManager: .default,
            commandRunner: RemoteShellCommandRunner(fileManager: .default)
        )
        let binaryPath = tempDir.appendingPathComponent("codex-tools-proxyd", isDirectory: false)
        try writeExecutableStub(to: binaryPath)

        let shouldReuse = try builder.prepareBinaryPathForBuild(binaryPath, forceRebuild: false)

        XCTAssertTrue(shouldReuse)
        XCTAssertTrue(FileManager.default.fileExists(atPath: binaryPath.path))
    }

    private func writeExecutableStub(to url: URL) throws {
        try Data("#!/bin/sh\nexit 0\n".utf8).write(to: url)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: url.path
        )
    }
}
