# LEF Physical Schema

## Purpose and Scope

Own `LEFLayerDef` and associated spacing/enclosure records.
Parent: [LEF](../DESIGN.md). No children.

## Responsibilities and Boundaries

Retain declared physical layer values. Use TechIR's shared axis value rather than
a lossy scalar projection. Rule evaluation belongs to domain engines.

## Related Designs

| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [LEF](../DESIGN.md) | Parent | Physical layer schema | Supported standard values | Missing declarations remain missing |
| [TechnologyGrid](../../TechIR/TechnologyGrid/DESIGN.md) | Depends on | IRTechAxisValue | Micrometer pitch/offset | No implicit axis selection |

## Architecture

```mermaid
flowchart LR
  Grid[IRTechAxisValue] --> Layer[LEFLayerDef] --> Codec
```

## Contracts and Invariants

Scalar and X/Y pitch/offset declarations remain distinguishable. Optional rules
remain optional. Records have value ownership and identical semantics on all
targets.

## Verification and Change Impact

LEF reader/writer and TechIR conversion tests own grid preservation. Native
consumers must validate process mapping and choose an axis explicitly.
