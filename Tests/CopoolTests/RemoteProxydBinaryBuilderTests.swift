import XCTest
import Compression
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

        let resolved = try builder.prebuiltBinary(
            for: RemoteLinuxPlatform(
                primaryTarget: target,
                fallbackTarget: "x86_64-unknown-linux-gnu"
            )
        )

        XCTAssertEqual(resolved?.path, binaryPath.path)
    }

    func testPrebuiltBinaryUsesBundledCompressedArtifactForTarget() throws {
        let fileManager = FileManager.default
        let tempDir = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fileManager.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: tempDir) }

        let resourcesRoot = tempDir.appendingPathComponent("Resources", isDirectory: true)
        let cacheRoot = tempDir.appendingPathComponent("ApplicationSupport", isDirectory: true)
        let target = "aarch64-unknown-linux-musl"
        let archivePath = resourcesRoot
            .appendingPathComponent("proxyd-prebuilt-archives", isDirectory: true)
            .appendingPathComponent(target, isDirectory: true)
            .appendingPathComponent("codex-tools-proxyd.zlib", isDirectory: false)
        try fileManager.createDirectory(at: archivePath.deletingLastPathComponent(), withIntermediateDirectories: true)
        try writeCompressedStub(to: archivePath)

        let builder = RemoteProxydBinaryBuilder(
            repoRoot: nil,
            bundledResourceRoot: resourcesRoot,
            prebuiltCacheRoot: cacheRoot,
            fileManager: fileManager,
            commandRunner: RemoteShellCommandRunner(fileManager: fileManager)
        )

        let resolved = try builder.prebuiltBinary(forTarget: target)

        XCTAssertEqual(
            resolved?.path,
            cacheRoot
                .appendingPathComponent("proxyd-prebuilt", isDirectory: true)
                .appendingPathComponent(target, isDirectory: true)
                .appendingPathComponent("codex-tools-proxyd", isDirectory: false)
                .path
        )
    }

    func testPrebuiltBinaryExtractsBundledCompressedArtifactToCacheRoot() throws {
        let fileManager = FileManager.default
        let tempDir = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fileManager.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: tempDir) }

        let resourcesRoot = tempDir.appendingPathComponent("Resources", isDirectory: true)
        let cacheRoot = tempDir.appendingPathComponent("ApplicationSupport", isDirectory: true)
        let target = "aarch64-unknown-linux-musl"
        let compressedPath = resourcesRoot
            .appendingPathComponent("proxyd-prebuilt-archives", isDirectory: true)
            .appendingPathComponent(target, isDirectory: true)
            .appendingPathComponent("codex-tools-proxyd.zlib", isDirectory: false)
        try fileManager.createDirectory(at: compressedPath.deletingLastPathComponent(), withIntermediateDirectories: true)
        try writeCompressedStub(to: compressedPath)

        let builder = RemoteProxydBinaryBuilder(
            repoRoot: nil,
            bundledResourceRoot: resourcesRoot,
            prebuiltCacheRoot: cacheRoot,
            fileManager: fileManager,
            commandRunner: RemoteShellCommandRunner(fileManager: fileManager)
        )

        let resolved = try XCTUnwrap(builder.prebuiltBinary(forTarget: target))

        XCTAssertEqual(
            resolved.path,
            cacheRoot
                .appendingPathComponent("proxyd-prebuilt", isDirectory: true)
                .appendingPathComponent(target, isDirectory: true)
                .appendingPathComponent("codex-tools-proxyd", isDirectory: false)
                .path
        )
        XCTAssertTrue(fileManager.fileExists(atPath: resolved.path))
        XCTAssertTrue(fileManager.isExecutableFile(atPath: resolved.path))
        XCTAssertEqual(try String(contentsOf: resolved), "#!/bin/sh\nexit 0\n")
    }

    private func writeExecutableStub(to url: URL) throws {
        try Data("#!/bin/sh\nexit 0\n".utf8).write(to: url)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: url.path
        )
    }

    private func writeCompressedStub(to url: URL) throws {
        let source = Data("#!/bin/sh\nexit 0\n".utf8)
        try compress(source).write(to: url)
    }

    private func compress(_ data: Data) throws -> Data {
        let destinationCapacity = max(64, data.count * 2)
        return try data.withUnsafeBytes { sourceBuffer in
            guard let sourceBaseAddress = sourceBuffer.bindMemory(to: UInt8.self).baseAddress else {
                throw NSError(domain: "RemoteProxydBinaryBuilderTests", code: 1)
            }
            let destination = UnsafeMutablePointer<UInt8>.allocate(capacity: destinationCapacity)
            defer { destination.deallocate() }

            let compressedCount = compression_encode_buffer(
                destination,
                destinationCapacity,
                sourceBaseAddress,
                data.count,
                nil,
                COMPRESSION_ZLIB
            )
            XCTAssertGreaterThan(compressedCount, 0)
            return Data(bytes: destination, count: compressedCount)
        }
    }
}
