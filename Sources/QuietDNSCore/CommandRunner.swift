import Foundation

public struct CommandResult {
    public let code: Int32
    public let output: String
}

public enum CommandRunner {
    /// No shell; all arguments remain separate. Stdout/stderr share a drained pipe.
    public static func run(_ executable: String, _ arguments: [String]) throws -> CommandResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe; process.standardError = pipe
        process.standardInput = FileHandle.nullDevice
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return CommandResult(code: process.terminationStatus, output: String(decoding: data, as: UTF8.self))
    }

    /// osascript delegates authentication to the standard macOS administrator dialog.
    /// No password is requested by, stored in, or sent to QuietDNS.
    public static func administrator(helper: String, arguments: [String]) throws -> CommandResult {
        let command = ([helper] + arguments).map(Escaping.shell).joined(separator: " ")
        return try run("/usr/bin/osascript", ["-e", "do shell script \(Escaping.appleScript(command)) with administrator privileges"])
    }
}
