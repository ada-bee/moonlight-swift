enum StreamScreenMode: String, CaseIterable, Hashable {
    case windowed
    case fullscreen

    init(launchesFullscreen: Bool) {
        self = launchesFullscreen ? .fullscreen : .windowed
    }

    var launchesFullscreen: Bool {
        self == .fullscreen
    }

    var menuTitle: String {
        switch self {
        case .windowed:
            return "Windowed"
        case .fullscreen:
            return "Fullscreen"
        }
    }
}
