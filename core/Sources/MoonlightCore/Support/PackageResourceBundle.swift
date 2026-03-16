import Foundation

enum PackageResourceBundle {
    private static let executableTargetBundleName = "moonlight-swift_Moonlight.bundle"
    private static let coreTargetBundleName = "moonlight-swift_MoonlightCore.bundle"

    static var executableTarget: Bundle? {
        bundle(named: executableTargetBundleName)
    }

    static var coreTarget: Bundle? {
        bundle(named: coreTargetBundleName)
    }

    private static func bundle(named bundleName: String) -> Bundle? {
        for url in candidateURLs(for: bundleName) {
            if let bundle = Bundle(url: url) {
                return bundle
            }
        }

        return nil
    }

    private static func candidateURLs(for bundleName: String) -> [URL] {
        var urls: [URL] = []

        if let resourceURL = Bundle.main.resourceURL {
            urls.append(resourceURL.appendingPathComponent(bundleName, isDirectory: true))
        }

        urls.append(Bundle.main.bundleURL.appendingPathComponent(bundleName, isDirectory: true))

        if let executableDirectoryURL = Bundle.main.executableURL?.deletingLastPathComponent() {
            urls.append(executableDirectoryURL.appendingPathComponent(bundleName, isDirectory: true))
        }

        return urls
    }
}
