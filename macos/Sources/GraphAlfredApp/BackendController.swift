import Foundation

final class BackendController {
    private var process: Process?

    func ensureRunning(apiClient: APIClient) async throws {
        if await apiClient.healthCheck() {
            return
        }

        try startBackendProcessIfAvailable()

        for _ in 0..<30 {
            if await apiClient.healthCheck() {
                return
            }
            try await Task.sleep(nanoseconds: 150_000_000)
        }

        throw BackendError.startupTimeout
    }

    func stopIfOwned() {
        process?.terminate()
        process = nil
    }

    private func startBackendProcessIfAvailable() throws {
        guard process == nil else { return }

        guard let executable = resolveExecutablePath() else {
            throw BackendError.executableNotFound
        }

        let backend = Process()
        backend.executableURL = executable
        backend.arguments = []

        backend.standardOutput = FileHandle.standardOutput
        backend.standardError = FileHandle.standardError

        try backend.run()
        process = backend
    }

    private func resolveExecutablePath() -> URL? {
        let fileManager = FileManager.default

        if let envPath = ProcessInfo.processInfo.environment["GRAPHALFRED_BACKEND_PATH"],
           fileManager.isExecutableFile(atPath: envPath) {
            return URL(fileURLWithPath: envPath)
        }

        let cwd = fileManager.currentDirectoryPath
        let candidates = [
            "\(cwd)/backend/target/debug/graphalfred-backend",
            "\(cwd)/backend/target/release/graphalfred-backend",
            "\(cwd)/target/debug/graphalfred-backend",
            "\(cwd)/target/release/graphalfred-backend"
        ]

        for candidate in candidates where fileManager.isExecutableFile(atPath: candidate) {
            return URL(fileURLWithPath: candidate)
        }

        return nil
    }
}

enum BackendError: LocalizedError {
    case executableNotFound
    case startupTimeout

    var errorDescription: String? {
        switch self {
        case .executableNotFound:
            return "Rust backend binary not found. Build it with `cargo build` inside `backend/`."
        case .startupTimeout:
            return "Rust backend did not start in time."
        }
    }
}
