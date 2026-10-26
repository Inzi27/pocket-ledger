// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "PocketLedger",
    platforms: [.iOS("27.0"), .macOS(.v14)],
    products: [
        .library(name: "BudgetCore", targets: ["BudgetCore"]),
        .library(name: "BudgetStore", targets: ["BudgetStore"])
    ],
    targets: [
        .target(name: "BudgetCore"),
        .target(name: "BudgetStore", dependencies: ["BudgetCore"]),
        // This target checks the shared UI using the macOS SDK when Xcode is absent.
        // Install the iPhone app using the Xcode project, not this executable.
        .executableTarget(name: "PocketLedgerCheck", dependencies: ["BudgetCore", "BudgetStore"],
                          path: "App", exclude: ["Resources"]),
        .testTarget(name: "BudgetCoreTests", dependencies: ["BudgetCore"]),
        .testTarget(name: "BudgetStoreTests", dependencies: ["BudgetStore", "BudgetCore"])
    ],
    swiftLanguageVersions: [.v5]
)
