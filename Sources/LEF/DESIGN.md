# LEF

## Purpose and Scope

This module owns LEF parsing, writing and explicit projections into LayoutIR and
TechIR. Parent: [swift-mask-data](../../DESIGN.md). Child:
[GeometryConversion](GeometryConversion/DESIGN.md).

## Responsibilities and Boundaries

The reader retains supported LEF declarations. The geometry converter owns the
micrometer-to-DBU boundary; process interpretation and qualification belong to
consumers. Generated labels are display data, not physical pin access shapes.

## Related Designs

| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [Package](../../DESIGN.md) | Parent | Exact standard boundary | Independent codec product | Parsing alone is not full semantic closure |
| [GeometryConversion](GeometryConversion/DESIGN.md) | Child | Exact physical coordinates | LEF to LayoutIR conversion | Source geometry cannot be silently rounded |
| [PDKKit](../../../PDKKit/DESIGN.md) | Used by | LEFDocument and typed errors | Process-view inspection | Inventory success does not prove executable process semantics |

## Architecture

```mermaid
flowchart LR
  Bytes --> Reader[LEFLibraryReader] --> Document[LEFDocument]
  Document --> Geometry[GeometryConversion] --> LayoutIR
  Document --> Technology[LEFTechIRConverter] --> TechIR
  Document --> Writer[LEFLibraryWriter] --> Bytes
```

## Contracts and Invariants

Unsupported syntax and invalid numeric input fail explicitly. Supported source
physical coordinates must be representable on the document's DBU grid and within
LayoutIR's Int32 range. Binary floating-point noise is distinguished from actual
sub-DBU geometry at the conversion boundary.

## Verification and Change Impact

[LEFTests](../../Tests/LEFTests) owns parser, conversion and error behavior.
Geometry changes first prove the child contract, then the LEF and package paths.
Consumers retaining LEFDocument must verify their own semantic projection; this
module's tests do not prove native placement, routing or extraction.
