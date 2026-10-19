# LEF

## Purpose and Scope

This module owns LEF parsing, writing and explicit projections into LayoutIR and
TechIR. Parent: [swift-mask-data](../../DESIGN.md). Child:
[GeometryConversion](GeometryConversion/DESIGN.md),
[Codec](Codec/DESIGN.md), and [PhysicalSchema](PhysicalSchema/DESIGN.md).

## Responsibilities and Boundaries

The reader retains supported LEF declarations. The geometry converter owns the
micrometer-to-DBU boundary; process interpretation and qualification belong to
consumers. Generated labels are display data, not physical pin access shapes.

## Related Designs

| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [Package](../../DESIGN.md) | Parent | Exact standard boundary | Independent codec product | Parsing alone is not full semantic closure |
| [GeometryConversion](GeometryConversion/DESIGN.md) | Child | Exact physical coordinates | LEF to LayoutIR conversion | Source geometry cannot be silently rounded |
| [Codec](Codec/DESIGN.md) | Child | Strict reader/writer | Standard declarations | Unsupported arity fails rather than dropping values |
| [PhysicalSchema](PhysicalSchema/DESIGN.md) | Child | Typed layers and PORT/OBS paths | Numeric layer and path semantics | Scalar and two-axis grids remain distinguishable; each path owns its width |
| [TechnologyUnits](../TechIR/TechnologyUnits/DESIGN.md) | Depends on | IRTechUnitDeclarations | Retained precision facts | Codec validation and numerical interpretation have separate owners |
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
`PITCH` and `OFFSET` retain either a scalar or an explicit X/Y pair. Their
representation is shared with TechIR; consumers select the relevant axis rather
than assuming the first value is the routing pitch. Scalar numeric statements
must have exactly their supported arity.

The optional document-level `manufacturingGrid` retains microns independently
of database units. [Codec](Codec/DESIGN.md) owns source/writer validation and
legacy serialization behavior. LEF/TechIR projection retains this field in both
directions; consumers own exact process-grid enforcement.

The document retains electrical precision declarations through
[TechnologyUnits](../TechIR/TechnologyUnits/DESIGN.md); [Codec](Codec/DESIGN.md)
owns valid spellings, numeric rules and standard omitted-database semantics.

The optional obstruction minimum-width policy is retained through TechIR;
[Codec](Codec/DESIGN.md) owns source syntax and [Native ProcessInputs](../../../PhysicalDesignEngine/Sources/PhysicalDesignCore/ProcessInputs/DESIGN.md)
owns exact bundle interpretation.

Ordered layer antenna declarations use [TechnologyAntenna](../TechIR/TechnologyAntenna/DESIGN.md); [Codec](Codec/DESIGN.md) validates source laws without granting process admission.

[TechnologyEnclosure](../TechIR/TechnologyEnclosure/DESIGN.md) owns exact layer enclosure facts; scalar inter-layer projection requires separate stack identities and is not fabricated.

Layer electrical resistance keeps sheet ohms/square distinct from cut ohms through [PhysicalSchema](PhysicalSchema/DESIGN.md) and [TechnologyGrid](../TechIR/TechnologyGrid/DESIGN.md).

[TechnologyCurrentDensity](../TechIR/TechnologyCurrentDensity/DESIGN.md) retains standard scalar electrical limits; source/provider reconciliation belongs to electrical signoff rather than geometric placement/routing.

[TechnologyViaGeneration](../TechIR/TechnologyViaGeneration/DESIGN.md) retains library-level via formulas separately from instantiated VIA geometry; [Codec](Codec/DESIGN.md#via-generation-formulas) owns strict syntax.

## Verification and Change Impact

[LEFTests](../../Tests/LEFTests) owns parser, conversion and error behavior.
Geometry changes first prove the child contract, then the LEF and package paths.
Consumers retaining LEFDocument must verify their own semantic projection; this
module's tests do not prove native placement, routing or extraction.

Property definition facts use [TechnologyProperties](../TechIR/TechnologyProperties/DESIGN.md); codec retention includes typed layer assignments and recognized subtypes, but does not admit property-based process application.
