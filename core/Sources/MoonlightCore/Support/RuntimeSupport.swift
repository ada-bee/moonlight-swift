import Foundation
import VideoToolbox

public enum RuntimeSupport {
    public enum Failure: Sendable {
        case unsupportedOperatingSystem
        case hardwareAV1DecodeUnavailable

        public var message: String {
            switch self {
            case .unsupportedOperatingSystem:
                return "macOS 26 or newer is required."
            case .hardwareAV1DecodeUnavailable:
                return RuntimeSupport.av1HardwareDecodeRequirementMessage
            }
        }
    }

    public struct Status: Sendable {
        public let failure: Failure?

        public var isSupported: Bool {
            failure == nil
        }

        public var failureMessage: String? {
            failure?.message
        }

        fileprivate init(failure: Failure? = nil) {
            self.failure = failure
        }
    }

    public static let minimumOperatingSystemVersion = OperatingSystemVersion(
        majorVersion: 26,
        minorVersion: 0,
        patchVersion: 0
    )

    public static let av1HardwareDecodeRequirementMessage = "AV1 hardware decode support is required."

    public static func currentStatus(processInfo: ProcessInfo = .processInfo) -> Status {
        guard processInfo.isOperatingSystemAtLeast(minimumOperatingSystemVersion) else {
            return Status(failure: .unsupportedOperatingSystem)
        }

        guard VTIsHardwareDecodeSupported(kCMVideoCodecType_AV1) else {
            return Status(failure: .hardwareAV1DecodeUnavailable)
        }

        return Status()
    }
}
