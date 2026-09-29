//
//  Log.swift — a tiny append-only log at ~/Library/Logs/Improvements.log.
//

import Foundation

enum Log {
    static let url = URL(fileURLWithPath: NSHomeDirectory())
        .appendingPathComponent("Library/Logs/Improvements.log")

    private static let lock = NSLock()

    static func write(_ message: String) {
        lock.lock(); defer { lock.unlock() }
        let line = "\(Date()) \(message)\n"
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                 withIntermediateDirectories: true)
        if let handle = try? FileHandle(forWritingTo: url) {
            _ = handle.seekToEndOfFile()
            handle.write(Data(line.utf8))
            try? handle.close()
        } else {
            try? line.write(to: url, atomically: true, encoding: .utf8)
        }
    }

    /// Runs a helper tool and returns its exit status.
    @discardableResult
    static func run(_ path: String, _ arguments: [String]) -> Int32 {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: path)
        task.arguments = arguments
        task.standardOutput = Pipe()
        task.standardError = Pipe()
        do {
            try task.run()
            task.waitUntilExit()
            return task.terminationStatus
        } catch {
            write("failed to run \(path) \(arguments.joined(separator: " ")): \(error.localizedDescription)")
            return -1
        }
    }
}
