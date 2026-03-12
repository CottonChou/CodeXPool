import Foundation

struct CommandResult {
    var status: Int32
    var stdout: String
    var stderr: String
}

enum CommandRunner {
    @discardableResult
    static func run(
        _ launchPath: String,
        arguments: [String] = [],
        environment: [String: String]? = nil,
        currentDirectory: URL? = nil
    ) throws -> CommandResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: launchPath)
        process.arguments = arguments

        if let environment {
            process.environment = ProcessInfo.processInfo.environment.merging(environment) { _, new in new }
        }

        if let currentDirectory {
            process.currentDirectoryURL = currentDirectory
        }

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        do {
            try process.run()
        } catch {
            let command = "\(launchPath) \(arguments.joined(separator: " "))"
            throw AppError.io(L10n.tr("error.shell.run_failed_format", command, error.localizedDescription))
        }

        process.waitUntilExit()
        let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()

        let stdout = String(data: stdoutData, encoding: .utf8) ?? ""
        let stderr = String(data: stderrData, encoding: .utf8) ?? ""

        let result = CommandResult(status: process.terminationStatus, stdout: stdout, stderr: stderr)
        return result
    }

    static func runChecked(
        _ launchPath: String,
        arguments: [String] = [],
        environment: [String: String]? = nil,
        currentDirectory: URL? = nil,
        errorPrefix: String
    ) throws -> CommandResult {
        let result = try run(launchPath, arguments: arguments, environment: environment, currentDirectory: currentDirectory)
        guard result.status == 0 else {
            let details = result.stderr.isEmpty ? result.stdout : result.stderr
            throw AppError.io("\(errorPrefix): \(details.trimmingCharacters(in: .whitespacesAndNewlines))")
        }
        return result
    }

    static func resolveExecutable(_ name: String) -> String? {
        guard let result = try? run("/usr/bin/env", arguments: ["which", name]), result.status == 0 else {
            return nil
        }
        let path = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        return path.isEmpty ? nil : path
    }
}
