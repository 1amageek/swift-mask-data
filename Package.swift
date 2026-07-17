// swift-tools-version: 6.3
import PackageDescription
import Foundation

let workspaceRoot = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
let isLSIWorkspace = FileManager.default.fileExists(
    atPath: workspaceRoot.appendingPathComponent("docs/workspace-packages.json").path
)
let circuiteFoundationDependency: Package.Dependency = isLSIWorkspace && FileManager.default.fileExists(
    atPath: workspaceRoot.appendingPathComponent("CircuiteFoundation/Package.swift").path
)
    ? .package(path: "../CircuiteFoundation")
    : .package(
        url: "https://github.com/1amageek/CircuiteFoundation.git",
        revision: "7abcac83517935c9b9f7553d7016d62cffde259d"
    )

let package = Package(
    name: "swift-mask-data",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "LayoutIR", targets: ["LayoutIR"]),
        .library(name: "GDSII", targets: ["GDSII"]),
        .library(name: "OASIS", targets: ["OASIS"]),
        .library(name: "FormatDetector", targets: ["FormatDetector"]),
        .library(name: "CIF", targets: ["CIF"]),
        .library(name: "LEF", targets: ["LEF"]),
        .library(name: "DEF", targets: ["DEF"]),
        .library(name: "DXF", targets: ["DXF"]),
        .library(name: "MaskGeometry", targets: ["MaskGeometry"]),
        .library(name: "TechIR", targets: ["TechIR"]),
    ],
    dependencies: [
        circuiteFoundationDependency,
    ],
    targets: [
        .target(
            name: "LayoutIR",
            dependencies: [
                .product(name: "CircuiteFoundation", package: "CircuiteFoundation"),
            ]
        ),
        .target(
            name: "GDSII",
            dependencies: [
                "LayoutIR",
                .product(name: "CircuiteFoundation", package: "CircuiteFoundation"),
            ]
        ),
        .target(
            name: "OASIS",
            dependencies: [
                "LayoutIR",
                .product(name: "CircuiteFoundation", package: "CircuiteFoundation"),
            ]
        ),
        .target(name: "FormatDetector", dependencies: ["LayoutIR"]),
        .target(
            name: "CIF",
            dependencies: [
                "LayoutIR",
                .product(name: "CircuiteFoundation", package: "CircuiteFoundation"),
            ]
        ),
        .target(name: "TechIR"),
        .target(
            name: "LEF",
            dependencies: [
                "LayoutIR",
                "TechIR",
                .product(name: "CircuiteFoundation", package: "CircuiteFoundation"),
            ]
        ),
        .target(
            name: "DEF",
            dependencies: [
                "LayoutIR",
                .product(name: "CircuiteFoundation", package: "CircuiteFoundation"),
            ]
        ),
        .target(
            name: "DXF",
            dependencies: [
                "LayoutIR",
                .product(name: "CircuiteFoundation", package: "CircuiteFoundation"),
            ]
        ),
        .target(name: "MaskGeometry", dependencies: ["LayoutIR"]),
        .testTarget(
            name: "LayoutIRTests",
            dependencies: [
                "LayoutIR",
                .product(name: "CircuiteFoundation", package: "CircuiteFoundation"),
            ]
        ),
        .testTarget(
            name: "GDSIITests",
            dependencies: [
                "GDSII",
                "LayoutIR",
                .product(name: "CircuiteFoundation", package: "CircuiteFoundation"),
            ]
        ),
        .testTarget(
            name: "OASISTests",
            dependencies: [
                "OASIS",
                "GDSII",
                "LayoutIR",
                .product(name: "CircuiteFoundation", package: "CircuiteFoundation"),
            ]
        ),
        .testTarget(
            name: "FormatDetectorTests",
            dependencies: [
                "FormatDetector",
                "GDSII",
                "OASIS",
                .product(name: "CircuiteFoundation", package: "CircuiteFoundation"),
            ]
        ),
        .testTarget(
            name: "CIFTests",
            dependencies: [
                "CIF",
                "LayoutIR",
                .product(name: "CircuiteFoundation", package: "CircuiteFoundation"),
            ]
        ),
        .testTarget(name: "TechIRTests", dependencies: ["TechIR"]),
        .testTarget(
            name: "LEFTests",
            dependencies: [
                "LEF",
                "LayoutIR",
                "TechIR",
                .product(name: "CircuiteFoundation", package: "CircuiteFoundation"),
            ]
        ),
        .testTarget(
            name: "DEFTests",
            dependencies: [
                "DEF",
                "LayoutIR",
                .product(name: "CircuiteFoundation", package: "CircuiteFoundation"),
            ]
        ),
        .testTarget(
            name: "DXFTests",
            dependencies: [
                "DXF",
                "LayoutIR",
                .product(name: "CircuiteFoundation", package: "CircuiteFoundation"),
            ]
        ),
        .testTarget(name: "MaskGeometryTests", dependencies: ["MaskGeometry", "LayoutIR"]),
        .testTarget(
            name: "GoldenCorpusTests",
            dependencies: [
                "LayoutIR",
                "GDSII",
                "OASIS",
                "LEF",
                "DEF",
                "FormatDetector",
                .product(name: "CircuiteFoundation", package: "CircuiteFoundation"),
            ]
        ),
    ]
)
