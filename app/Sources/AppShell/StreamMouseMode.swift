enum StreamMouseMode: Equatable {
    case absolute
    case raw

    init(usesRawMouse: Bool) {
        self = usesRawMouse ? .raw : .absolute
    }

    var usesRawMouse: Bool {
        self == .raw
    }

    var menuTitle: String {
        switch self {
        case .absolute:
            return "Pointer Input"
        case .raw:
            return "Direct Mouse Input"
        }
    }
}
