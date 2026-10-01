# DEF

## Purpose and Scope

Own standard DEF values, text I/O and LayoutIR interchange.
Parent: [package](../../DESIGN.md). Child: [Interchange](Interchange/DESIGN.md).

## Responsibilities and Boundaries

Standard orientation semantics belong here. Placement bounding-box normalization,
LEF master origin adjustment and process qualification belong to consuming engines.
The existing reader/writer remains a bounded standard subset, not signoff evidence.

## Related Designs

| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [Package](../../DESIGN.md) | parent | Standard-first geometry and units | Standard I/O boundary | No process qualification |
| [Interchange](Interchange/DESIGN.md) | child | DEF orientation and IR mapping | Exact transform meaning | Unsupported transforms fail |
| [PhysicalDesignCore](../../../PhysicalDesignEngine/Sources/PhysicalDesignCore/DESIGN.md) | used by | Standard orientation values and mapping | Native master geometry | Engine owns lower-left placement adjustment |

## Architecture

```text
DEFDocument -> Interchange -> LayoutIR -> Interchange -> DEFDocument
DEFOrientation -> orthogonal unit IRTransform -> native geometry consumers
```

## Contracts and Invariants

Interchange owns exact standard orientation interpretation. Public DEF values do
not imply a LEF master size, cell pin location or qualified process connectivity.

## Verification and Change Impact

DEFTests owns orientation semantics and format behavior. Native consumers separately
prove master, origin, pin, site and via preparation with the same standard transforms.
