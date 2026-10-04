// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "CalendarShareKit",
    platforms: [.iOS(.v17), .macOS(.v13)],
    products: [
        .library(name: "CalendarDomain", targets: ["CalendarDomain"]),
        .library(name: "MessageCodec", targets: ["MessageCodec"]),
        .library(name: "SharedStore", targets: ["SharedStore"]),
        .library(name: "EventKitProvider", targets: ["EventKitProvider"]),
        .library(name: "AuthorizationStore", targets: ["AuthorizationStore"]),
        .library(name: "GoogleCalendarProvider", targets: ["GoogleCalendarProvider"])
    ],
    dependencies: [
        .package(url: "https://github.com/openid/AppAuth-iOS.git", exact: "1.7.6")
    ],
    targets: [
        .target(name: "CalendarDomain"),
        .target(name: "MessageCodec", dependencies: ["CalendarDomain"]),
        .target(name: "SharedStore", dependencies: ["CalendarDomain"]),
        .target(name: "EventKitProvider", dependencies: ["CalendarDomain"]),
        .target(name: "AuthorizationStore", dependencies: [
            "CalendarDomain", "SharedStore",
            .product(name: "AppAuthCore", package: "AppAuth-iOS")
        ]),
        .target(name: "GoogleCalendarProvider", dependencies: ["CalendarDomain", "AuthorizationStore"]),
        .testTarget(name: "CalendarShareKitTests", dependencies: [
            "CalendarDomain", "MessageCodec", "SharedStore", "AuthorizationStore", "GoogleCalendarProvider"
        ])
    ]
)
