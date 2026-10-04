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

Interchange owns exact standard orientation interpretation and routing-point geometry.
The reader preserves explicit regular/special point extensions and rejects unsupported
route profiles before returning a successful document. Public DEF values do
not imply a LEF master size, cell pin location or qualified process connectivity.

### PINS admission

`DEFLibraryReader.read` owns atomic pin syntax admission before returning a document.
The existing `DEFPin` represents one implicit rectangular port, its layer rectangles,
one placement/orientation, direction/use, net, special flag and properties. One explicit
`PORT` before geometry is semantically that same port and may normalize to it. A second
port, polygon, pin via, layer mask/spacing/design-rule-width or other unrepresented pin
clause fails with `unsupportedPinFeature`; geometry is never partially accepted.
Unknown direction/use/orientation values fail with `invalidPinValue`, and malformed
supported point syntax fails with `invalidPinSyntax`. Missing optional attributes stay
absent; unsupported values never become nil or the default N orientation. Multiple
placements cannot overwrite an earlier pose. Raw coordinates remain in source DEF DBU.
This is a bounded reader profile, not a full DEF grammar or process validation.

The grammar authority is the Cadence *LEF/DEF 5.8 Language Reference*, Pins pp.279–280
and 288–289 ([reference PDF](https://www.kaixinspace.com/wp-content/uploads/2025/02/lefdefref.pdf)).
PORT connectivity partitions cannot be reconstructed from flat rectangles; downstream
consumers therefore rely on parser admission rather than scanning original text.

| Input | Output | Behavioral owner |
|---|---|---|
| Rectangular single port, standard direction/use/pose | Exact supported AST and writer round trip | DEF pin admission tests |
| Supported rectangle plus unrepresented shape/port | Typed unsupported, no returned document | DEF pin admission tests |
| Unknown enum value or malformed point/pose | Typed invalid, no returned document | DEF pin admission tests |

## Verification and Change Impact

DEFTests owns orientation semantics and format behavior. Native consumers separately
prove master, origin, pin, site and via preparation with the same standard transforms.
