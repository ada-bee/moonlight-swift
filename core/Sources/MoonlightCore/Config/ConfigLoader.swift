import Foundation

public enum ConfigLoaderError: Error, LocalizedError {
    case invalidJSON(URL, Error)

    public var errorDescription: String? {
        switch self {
        case let .invalidJSON(url, error):
            return "Invalid config JSON at \(url.path): \(error.localizedDescription)"
        }
    }
}

public struct ConfigLoader {
    public let fileManager: FileManager
    public let decoder: JSONDecoder

    private let currentDirectoryURL: URL
    private let executableURL: URL

    public init(fileManager: FileManager = .default, decoder: JSONDecoder = JSONDecoder()) {
        self.fileManager = fileManager
        self.decoder = decoder
        self.currentDirectoryURL = URL(fileURLWithPath: fileManager.currentDirectoryPath, isDirectory: true)

        let argv0 = CommandLine.arguments.first ?? ""
        if argv0.hasPrefix("/") {
            self.executableURL = URL(fileURLWithPath: argv0)
        } else {
            self.executableURL = currentDirectoryURL.appendingPathComponent(argv0)
        }
    }

    public func load() throws -> MVPConfiguration {
        let candidates = candidateConfigURLs()

        for url in candidates where fileManager.fileExists(atPath: url.path) {
            do {
                let data = try Data(contentsOf: url)
                return try decoder.decode(MVPConfiguration.self, from: data)
            } catch {
                throw ConfigLoaderError.invalidJSON(url, error)
            }
        }

        return fallbackForRuntime()
    }

    public func candidateConfigURLs() -> [URL] {
        let filenames = ["configs/local.json", "configs/mvp.sample.json"]
        var results: [URL] = []
        var seen: Set<String> = []

        for root in searchRoots() {
            for filename in filenames {
                let url = root.appendingPathComponent(filename)
                if seen.insert(url.path).inserted {
                    results.append(url)
                }
            }
        }

        return results
    }

    public func fallbackForRuntime() -> MVPConfiguration {
        MVPConfiguration.fallback
    }

    private func searchRoots() -> [URL] {
        var roots: [URL] = []
        var seen: Set<String> = []

        let directRoots = [
            currentDirectoryURL,
            executableURL.deletingLastPathComponent(),
            Bundle.main.bundleURL.deletingLastPathComponent()
        ]

        for root in directRoots {
            for ancestor in pathAncestors(of: root) {
                if seen.insert(ancestor.path).inserted {
                    roots.append(ancestor)
                }
            }
        }

        return roots
    }

    private func pathAncestors(of start: URL) -> [URL] {
        var results: [URL] = []
        var currentPath = start.standardizedFileURL.path

        while true {
            results.append(URL(fileURLWithPath: currentPath, isDirectory: true))
            let parentPath = (currentPath as NSString).deletingLastPathComponent
            if parentPath.isEmpty || parentPath == currentPath {
                break
            }
            currentPath = parentPath
        }

        if results.last?.path != "/" {
            results.append(URL(fileURLWithPath: "/", isDirectory: true))
        }

        return results
    }

}
