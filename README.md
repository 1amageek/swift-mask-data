# swift-mask-data

A pure-Swift library for reading, writing, and manipulating semiconductor mask layout data. Supports all major IC layout formats with a unified intermediate representation, enabling seamless format conversion, geometric operations, and design rule checks.

## Requirements

- Swift 6.2+
- macOS 26+

## Installation

Add to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/1amageek/swift-mask-data.git", from: "0.1.0")
]
```

Then add the modules you need:

```swift
.target(
    name: "YourTarget",
    dependencies: [
        .product(name: "GDSII", package: "swift-mask-data"),
        .product(name: "OASIS", package: "swift-mask-data"),
        .product(name: "GeometryOps", package: "swift-mask-data"),
        // ...
    ]
)
```

## Modules

| Module | Description |
|--------|-------------|
| **LayoutIR** | Unified intermediate representation for all layout formats |
| **GDSII** | GDSII Stream Format reader/writer |
| **OASIS** | OASIS (Open Artwork System Interchange Standard) reader/writer |
| **CIF** | Caltech Intermediate Form reader/writer |
| **LEF** | Library Exchange Format reader/writer |
| **DEF** | Design Exchange Format reader/writer |
| **DXF** | AutoCAD Drawing Exchange Format reader/writer |
| **FormatDetector** | Automatic layout format detection |
| **GeometryOps** | Boolean operations, sizing, and DRC on polygon regions |

## Quick Start

### Reading a GDSII file

```swift
import GDSII

let data = try Data(contentsOf: url)
let library = try GDSLibraryReader.read(data)

for cell in library.cells {
    print("Cell: \(cell.name), \(cell.elements.count) elements")
    for element in cell.elements {
        switch element {
        case .boundary(let b):
            print("  Boundary on layer \(b.layer)")
        case .path(let p):
            print("  Path on layer \(p.layer), width=\(p.width)")
        case .text(let t):
            print("  Text: \(t.string)")
        case .cellRef(let r):
            print("  Reference to \(r.cellName)")
        case .arrayRef(let a):
            print("  Array \(a.columns)x\(a.rows) of \(a.cellName)")
        }
    }
}
```

### Writing an OASIS file

```swift
import LayoutIR
import OASIS

let boundary = IRBoundary(
    layer: 1, datatype: 0,
    points: [
        IRPoint(x: 0, y: 0),
        IRPoint(x: 1000, y: 0),
        IRPoint(x: 1000, y: 500),
        IRPoint(x: 0, y: 500),
        IRPoint(x: 0, y: 0),
    ],
    properties: []
)

let cell = IRCell(name: "TOP", elements: [.boundary(boundary)])
let library = IRLibrary(name: "MYLIB", units: .default, cells: [cell])

let data = try OASISLibraryWriter.write(library)
try data.write(to: outputURL)
```

### Format conversion (GDSII to OASIS)

```swift
import GDSII
import OASIS

let gdsData = try Data(contentsOf: gdsURL)
let library = try GDSLibraryReader.read(gdsData)
let oasisData = try OASISLibraryWriter.write(library)
try oasisData.write(to: oasisURL)
```

### Auto-detecting file format

```swift
import FormatDetector
import GDSII
import OASIS

let data = try Data(contentsOf: url)
let format = FormatDetector.detect(data)

switch format {
case .gdsii:  let lib = try GDSLibraryReader.read(data)
case .oasis:  let lib = try OASISLibraryReader.read(data)
case .cif:    let lib = try CIFLibraryReader.read(data)
case .dxf:    let lib = try DXFLibraryReader.read(data)
case .lef:    let doc = try LEFLibraryReader.read(data)
case .def:    let doc = try DEFLibraryReader.read(data)
case .unknown: throw MyError.unsupportedFormat
}
```

### Geometric operations

```swift
import LayoutIR
import GeometryOps

let metal1 = Region(layer: 1, polygons: [poly1, poly2])
let metal2 = Region(layer: 2, polygons: [poly3])

// Boolean operations
let merged = metal1.or(metal2)
let overlap = metal1.and(metal2)
let difference = metal1.not(metal2)

// Sizing (grow/shrink)
let grown = metal1.sized(by: 50)
let shrunk = metal1.sized(by: -50, cornerMode: .octagonal)

// DRC checks
let widthErrors = metal1.widthViolations(minWidth: 100)
let spaceErrors = metal1.spaceViolations(to: metal2, minSpace: 200)
let encErrors = metal2.enclosureViolations(inner: metal1, minEnclosure: 50)
```

### Working with LEF/DEF

```swift
import LEF
import DEF

// Read a standard cell library
let lefData = try Data(contentsOf: lefURL)
let lefDoc = try LEFLibraryReader.read(lefData)

for macro in lefDoc.macros {
    print("Macro: \(macro.name), class: \(macro.macroClass ?? "?")")
    for pin in macro.pins {
        print("  Pin: \(pin.name), direction: \(pin.direction)")
    }
}

// Read a placed & routed design
let defData = try Data(contentsOf: defURL)
let defDoc = try DEFLibraryReader.read(defData)

print("Design: \(defDoc.designName)")
print("Components: \(defDoc.components.count)")
print("Nets: \(defDoc.nets.count)")
```

## Format Details

### LayoutIR (Intermediate Representation)

All format readers produce `IRLibrary`, the common data model:

| Type | Description |
|------|-------------|
| `IRLibrary` | Top-level container with name, units, cells, metadata |
| `IRCell` | Named cell containing elements |
| `IRElement` | Enum: `.boundary`, `.path`, `.text`, `.cellRef`, `.arrayRef` |
| `IRBoundary` | Closed polygon (layer, datatype, points, properties) |
| `IRPath` | Open polyline with width (layer, pathType, width, points) |
| `IRText` | Text label (layer, position, string, transform) |
| `IRCellRef` | Instance reference (cellName, origin, transform) |
| `IRArrayRef` | Array reference (cellName, columns, rows, referencePoints) |
| `IRTransform` | Geometric transform (mirrorX, magnification, angle) |
| `IRPoint` | Integer coordinate (x: Int32, y: Int32) |
| `IRUnits` | Database unit scale (default: 1000 DBU/um = 1nm resolution) |

### GDSII

Full GDSII Stream Format support including:

- Multi-XY records (polygons > 8191 vertices)
- BOX records (configurable via `GDSReadOptions.boxMode`)
- NODE records (skipped as non-geometric)
- BGNEXTN / ENDEXTN path extensions
- Excess-64 floating point (GDS Real8)
- Properties (PROPATTR / PROPVALUE)

### OASIS

OASIS 1.0 standard support including:

- CBLOCK compression (zlib deflate, transparent read)
- RECTANGLE, POLYGON, PATH, TEXT, PLACEMENT records
- TRAPEZOID, CTRAPEZOID (all 25 types), CIRCLE (polygon approximation)
- Modal variables for compact encoding
- Repetitions (types 0-11: reuse, uniform, arbitrary grids)
- Properties with multi-value support
- S-bit (square) rectangles

### CIF

Caltech Intermediate Form with:

- Box (B), Wire (W), Polygon (P), Text (9) commands
- Cell definitions (DS/DF) with 2-parameter and 3-parameter scale forms
- Cell references (C) with Mirror (M X/Y), Rotation (R), Translation (T)
- Configurable writer: wire mode (square/flush/round), scale factor

### LEF

Library Exchange Format including:

- Layer definitions (ROUTING, CUT, MASTERSLICE) with spacing tables, enclosures
- Via definitions with cut patterns and rules
- Macro definitions with pins, ports, obstructions, foreign references
- Site definitions for placement
- Polygon geometry in ports and obstructions
- Property definitions
- Conversion to/from IRLibrary via `LEFIRConverter`

### DEF

Design Exchange Format including:

- Components with placement status (PLACED, FIXED, COVER, UNPLACED)
- Pins with layer geometry and placement
- Nets with routing (ROUTED, NEW continuation segments, via references)
- Special nets with wide-wire routing and extension values
- Blockages (routing and placement)
- Tracks, GCell grids, regions, fills, groups
- Polygon die area
- Property definitions with RANGE
- Conversion to/from IRLibrary via `DEFIRConverter`

### DXF

AutoCAD Drawing Exchange Format including:

- LINE, LWPOLYLINE, CIRCLE, ARC, ELLIPSE, POINT
- HATCH with boundary edge parsing (line, arc, elliptical arc)
- INSERT with non-uniform scale, rotation, array patterns
- BLOCK definitions
- Configurable circle approximation segments
- Custom layer mapping (string layer names to numeric layer/datatype)

### GeometryOps

| Operation | API | Description |
|-----------|-----|-------------|
| **Union** | `region.or(other)` | Merge overlapping polygons |
| **Intersection** | `region.and(other)` | Find overlapping areas |
| **Difference** | `region.not(other)` | Subtract one region from another |
| **XOR** | `region.xor(other)` | Symmetric difference |
| **Sizing** | `region.sized(by:cornerMode:)` | Grow/shrink with corner control |
| **Width check** | `region.widthViolations(minWidth:metric:)` | Minimum width DRC |
| **Space check** | `region.spaceViolations(to:minSpace:metric:)` | Minimum spacing DRC |
| **Enclosure** | `region.enclosureViolations(inner:minEnclosure:metric:)` | Enclosure DRC |
| **Notch** | `region.notchViolations(minNotch:metric:)` | Notch DRC |
| **Separation** | `region.separationViolations(to:minSeparation:metric:)` | Edge separation DRC |
| **Grid** | `region.gridViolations(gridX:gridY:)` | Grid alignment check |
| **Angle** | `region.angleViolations(allowedAngles:)` | Allowed angle check |

Corner modes for sizing: `.square`, `.octagonal`, `.round(segments:)`

DRC metrics: `.euclidean`, `.square` (Chebyshev L-infinity), `.projection`

## Architecture

```
                    ┌──────────┐
                    │ LayoutIR │
                    └────┬─────┘
          ┌──────┬───────┼───────┬──────┬──────┐
          │      │       │       │      │      │
       ┌──┴──┐┌──┴──┐┌───┴──┐┌──┴──┐┌──┴──┐┌──┴──┐
       │GDSII││OASIS││ CIF  ││ DXF ││ LEF ││ DEF │
       └─────┘└─────┘└──────┘└─────┘└─────┘└─────┘

       ┌──────────────┐    ┌─────────────────┐
       │FormatDetector│    │  GeometryOps    │
       └──────────────┘    └─────────────────┘
```

- All format modules depend only on **LayoutIR**
- Format modules are independent of each other
- All types are value types (`struct` / `enum`), `Sendable`, and `Codable`

## Testing

```bash
swift test
```

557 tests across 37 suites covering round-trip correctness, edge cases, KLayout compatibility, and regression fixes.

## License

MIT
