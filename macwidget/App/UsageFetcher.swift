import Foundation

enum UsageFetcherError: Error {
    case missingScript
    case timedOut
    case failed(Int32)
    case invalidOutput
}

struct UsageFetcher {
    static func scriptPath() -> String? {
        if let override = ProcessInfo.processInfo.environment["QUOTAWIDGET_FETCH"] {
            return override
        }
        if let resourcePath = Bundle.main.resourcePath {
            let bundled = resourcePath + "/core/fetch_usage.py"
            if FileManager.default.fileExists(atPath: bundled) {
                return bundled
            }
        }
        let development = FileManager.default.currentDirectoryPath
            + "/../core/fetch_usage.py"
        return FileManager.default.fileExists(atPath: development)
            ? development : nil
    }

    static func fetch(timeout: TimeInterval = 30) throws -> String {
        guard let script = scriptPath() else {
            throw UsageFetcherError.missingScript
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        process.arguments = [script]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = Pipe()
        try process.run()

        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.05)
        }
        if process.isRunning {
            process.terminate()
            throw UsageFetcherError.timedOut
        }
        guard process.terminationStatus == 0 else {
            throw UsageFetcherError.failed(process.terminationStatus)
        }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        guard let json = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !json.isEmpty,
              (try? UsagePayload.decode(Data(json.utf8))) != nil else {
            throw UsageFetcherError.invalidOutput
        }
        return json
    }
}
