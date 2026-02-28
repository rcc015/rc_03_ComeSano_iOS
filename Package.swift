// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "ComeSano",
    platforms: [
        .iOS(.v17),
        .watchOS(.v10),
        .macOS(.v14)
    ],
    products: [
        .library(name: "ComeSanoCore", targets: ["ComeSanoCore"]),
        .library(name: "ComeSanoHealthKit", targets: ["ComeSanoHealthKit"]),
        .library(name: "ComeSanoUI", targets: ["ComeSanoUI"]),
        .library(name: "ComeSanoPersistence", targets: ["ComeSanoPersistence"]),
        .library(name: "ComeSanoAI", targets: ["ComeSanoAI"])
    ],
    targets: [
        .target(name: "ComeSanoCore"),
        .target(
            name: "ComeSanoHealthKit",
            dependencies: ["ComeSanoCore"]
        ),
        .target(
            name: "ComeSanoPersistence",
            dependencies: ["ComeSanoCore"]
        ),
        .target(
            name: "ComeSanoAI",
            dependencies: ["ComeSanoCore"]
        ),
        .target(
            name: "ComeSanoUI",
            dependencies: ["ComeSanoCore"]
        ),
        .testTarget(
            name: "ComeSanoCoreTests",
            dependencies: ["ComeSanoCore"]
        )
    ]
)
