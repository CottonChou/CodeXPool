import XCTest
@testable import Copool

final class RemoteProxydBinaryBuilderTests: XCTestCase {
    func testBundledManifestPathRestoresFlattenedBundledSourceTree() throws {
        let fileManager = FileManager.default
        let tempDir = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fileManager.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: tempDir) }

        let resourcesRoot = tempDir.appendingPathComponent("Resources", isDirectory: true)
        try fileManager.createDirectory(at: resourcesRoot, withIntermediateDirectories: true)

        try Data("[package]\nname = \"codex-tools-proxyd\"\nversion = \"0.0.0\"\nedition = \"2021\"\n".utf8)
            .write(to: resourcesRoot.appendingPathComponent("Cargo.toml"))
        try Data("".utf8).write(to: resourcesRoot.appendingPathComponent("Cargo.lock"))
        try Data("#[path = \"../../src/auth.rs\"]\nmod auth;\nfn main() {}\n".utf8)
            .write(to: resourcesRoot.appendingPathComponent("main.rs"))
        try Data("pub fn noop() {}\n".utf8)
            .write(to: resourcesRoot.appendingPathComponent("auth.rs"))
        try Data("".utf8).write(to: resourcesRoot.appendingPathComponent("models.rs"))
        try Data("".utf8).write(to: resourcesRoot.appendingPathComponent("proxy_daemon.rs"))
        try Data("".utf8).write(to: resourcesRoot.appendingPathComponent("proxy_service.rs"))
        try Data("".utf8).write(to: resourcesRoot.appendingPathComponent("state.rs"))
        try Data("".utf8).write(to: resourcesRoot.appendingPathComponent("store.rs"))
        try Data("".utf8).write(to: resourcesRoot.appendingPathComponent("usage.rs"))
        try Data("".utf8).write(to: resourcesRoot.appendingPathComponent("utils.rs"))

        let builder = RemoteProxydBinaryBuilder(
            repoRoot: nil,
            bundledResourceRoot: resourcesRoot,
            fileManager: fileManager,
            commandRunner: RemoteShellCommandRunner(fileManager: fileManager)
        )

        let manifestPath = try XCTUnwrap(builder.bundledManifestPath())
        let crateRoot = manifestPath.deletingLastPathComponent()
        let restoredSupportSource = crateRoot
            .deletingLastPathComponent()
            .appendingPathComponent("src/auth.rs", isDirectory: false)

        XCTAssertEqual(manifestPath.lastPathComponent, "Cargo.toml")
        XCTAssertTrue(fileManager.fileExists(atPath: crateRoot.appendingPathComponent("src/main.rs").path))
        XCTAssertTrue(fileManager.fileExists(atPath: restoredSupportSource.path))
    }

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

    func testPrebuiltBinaryPrefersRepoRootArtifactForTarget() throws {
        let fileManager = FileManager.default
        let tempDir = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fileManager.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: tempDir) }

        let target = "x86_64-unknown-linux-musl"
        let binaryPath = RepositoryLocator.proxydPrebuiltBinaryURL(in: tempDir, target: target)
        try fileManager.createDirectory(at: binaryPath.deletingLastPathComponent(), withIntermediateDirectories: true)
        try writeExecutableStub(to: binaryPath)

        let builder = RemoteProxydBinaryBuilder(
            repoRoot: tempDir,
            fileManager: fileManager,
            commandRunner: RemoteShellCommandRunner(fileManager: fileManager)
        )

        let resolved = builder.prebuiltBinary(
            for: RemoteLinuxPlatform(
                primaryTarget: target,
                fallbackTarget: "x86_64-unknown-linux-gnu"
            )
        )

        XCTAssertEqual(resolved?.path, binaryPath.path)
    }

    private func writeExecutableStub(to url: URL) throws {
        try Data("#!/bin/sh\nexit 0\n".utf8).write(to: url)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: url.path
        )
    }
}
