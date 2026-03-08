// swift-tools-version: 6.2
import Foundation
import PackageDescription

let environment = ProcessInfo.processInfo.environment
let openSSLPrefix = environment["OPENSSL_PREFIX"]
let openSSLIncludeDir = environment["OPENSSL_INCLUDE_DIR"] ?? openSSLPrefix.map { "\($0)/include" }
let openSSLLibDir = environment["OPENSSL_LIB_DIR"] ?? openSSLPrefix.map { "\($0)/lib" }

let openSSLCSettings = openSSLIncludeDir.map { [CSetting.unsafeFlags(["-I\($0)"])] } ?? []
let openSSLLinkerSettings =
    (openSSLLibDir.map { [LinkerSetting.unsafeFlags(["-L\($0)"])] } ?? [])
    + [.linkedLibrary("ssl"), .linkedLibrary("crypto")]

let package = Package(
    name: "moonlight-swift",
    platforms: [
        .macOS(.v26)
    ],
    products: [
        .executable(name: "Moonlight", targets: ["Moonlight"]),
        .library(name: "MoonlightCore", targets: ["MoonlightCore"])
    ],
    targets: [
        .target(
            name: "CEnet",
            path: "vendor/moonlight-common-c/enet",
            sources: [
                "callbacks.c",
                "compress.c",
                "host.c",
                "list.c",
                "packet.c",
                "peer.c",
                "protocol.c",
                "unix.c"
            ],
            publicHeadersPath: "include",
            cSettings: [
                .headerSearchPath("include"),
                .define("__APPLE_USE_RFC_3542", to: "1"),
                .define("HAS_FCNTL", to: "1"),
                .define("HAS_IOCTL", to: "1"),
                .define("HAS_POLL", to: "1"),
                .define("HAS_GETADDRINFO", to: "1"),
                .define("HAS_GETNAMEINFO", to: "1"),
                .define("HAS_INET_PTON", to: "1"),
                .define("HAS_INET_NTOP", to: "1"),
                .define("HAS_MSGHDR_FLAGS", to: "1"),
                .define("HAS_SOCKLEN_T", to: "1")
            ]
        ),
        .target(
            name: "CNanoRS",
            path: "vendor/moonlight-common-c",
            sources: [
                "nanors/deps/obl/oblas_lite.c"
            ],
            publicHeadersPath: "nanors",
            cSettings: [
                .headerSearchPath("nanors"),
                .headerSearchPath("nanors/deps/obl"),
                .headerSearchPath("nanors/deps"),
                .headerSearchPath("nanors/deps/simde")
            ]
        ),
        .target(
            name: "CMoonlightCommon",
            dependencies: ["CEnet", "CNanoRS"],
            path: "vendor/moonlight-common-c",
            exclude: [
                "enet",
                "nanors/deps/simde"
            ],
            sources: [
                "src/AudioStream.c",
                "src/ByteBuffer.c",
                "src/Connection.c",
                "src/ConnectionTester.c",
                "src/ControlStream.c",
                "src/FakeCallbacks.c",
                "src/InputStream.c",
                "src/LinkedBlockingQueue.c",
                "src/Misc.c",
                "src/Platform.c",
                "src/PlatformCrypto.c",
                "src/PlatformSockets.c",
                "src/RecorderCallbacks.c",
                "src/rswrapper.c",
                "src/RtpAudioQueue.c",
                "src/RtpVideoQueue.c",
                "src/RtspConnection.c",
                "src/RtspParser.c",
                "src/SdpGenerator.c",
                "src/SimpleStun.c",
                "src/VideoDepacketizer.c",
                "src/VideoStream.c"
            ],
            publicHeadersPath: "src",
            cSettings: [
                .headerSearchPath("src"),
                .headerSearchPath("nanors"),
                .headerSearchPath("nanors/deps/obl"),
                .headerSearchPath("nanors/deps"),
                .headerSearchPath("nanors/deps/simde"),
                .headerSearchPath("../vendor/moonlight-common-c/enet/include"),
                .define("__APPLE_USE_RFC_3542", to: "1"),
                .define("HAS_SOCKLEN_T")
            ] + openSSLCSettings,
            linkerSettings: openSSLLinkerSettings
        ),
        .target(
            name: "CMoonlightBridgeSupport",
            dependencies: ["CMoonlightCommon"],
            path: "core/cbridge",
            publicHeadersPath: ".",
            cSettings: [
                .headerSearchPath("../../vendor/moonlight-common-c/src")
            ] + openSSLCSettings,
            linkerSettings: openSSLLinkerSettings
        ),
        .target(
            name: "MoonlightCore",
            dependencies: ["CMoonlightCommon", "CMoonlightBridgeSupport"],
            path: "core/Sources/MoonlightCore",
            resources: [
                .process("Video/MetalRendererShaders.metal")
            ]
        ),
        .executableTarget(
            name: "Moonlight",
            dependencies: ["MoonlightCore"],
            path: "app/Sources/AppShell"
        )
    ]
)
