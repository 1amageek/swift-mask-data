// swift-tools-version: 6.2
import PackageDescription

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
        .library(name: "GeometryOps", targets: ["GeometryOps"]),
    ],
    targets: [
        .target(name: "LayoutIR"),
        .target(name: "GDSII", dependencies: ["LayoutIR"]),
        .target(name: "OASIS", dependencies: ["LayoutIR"]),
        .target(name: "FormatDetector", dependencies: ["LayoutIR"]),
        .target(name: "CIF", dependencies: ["LayoutIR"]),
        .target(name: "LEF", dependencies: ["LayoutIR"]),
        .target(name: "DEF", dependencies: ["LayoutIR"]),
        .target(name: "DXF", dependencies: ["LayoutIR"]),
        .target(name: "GeometryOps", dependencies: ["LayoutIR"]),
        .testTarget(name: "LayoutIRTests", dependencies: ["LayoutIR"]),
        .testTarget(name: "GDSIITests", dependencies: ["GDSII", "LayoutIR"]),
        .testTarget(name: "OASISTests", dependencies: ["OASIS", "GDSII", "LayoutIR"]),
        .testTarget(name: "FormatDetectorTests", dependencies: ["FormatDetector", "GDSII", "OASIS"]),
        .testTarget(name: "CIFTests", dependencies: ["CIF", "LayoutIR"]),
        .testTarget(name: "LEFTests", dependencies: ["LEF", "LayoutIR"]),
        .testTarget(name: "DEFTests", dependencies: ["DEF", "LayoutIR"]),
        .testTarget(name: "DXFTests", dependencies: ["DXF", "LayoutIR"]),
        .testTarget(name: "GeometryOpsTests", dependencies: ["GeometryOps", "LayoutIR"]),
    ]
)
