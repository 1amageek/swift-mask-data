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

### Routed PEX Source Intake

`DEFLibraryReader.readForRoutedPEX` returns `DEFSourceDocument`: the ordinary
document plus one explicit units declaration, its exact numeric literal and
zero-based tokenizer range (including `UNITS` through `;`). That range is not a
byte range. The consuming host binds the whole original artifact and its digest;
these source facts neither qualify extraction nor authorize a modified document.
The caller supplies a positive maximum source byte count, checked before decoding
or token allocation. Tokens and AST storage are bounded by that source size;
this is not a Foundation heap/RSS byte guarantee. Cancellation is checked during
tokenization and top-level/net/route traversal and before returning a result.
All storage is call-local and source buffers do not escape as borrowed pointers.

```text
Bounded original DEF -> strict codec -> document + declared units/token range
Original artifact identity ---------> host source binding -> routed PEX admission
```

This explicit source profile requires exactly one `UNITS DISTANCE MICRONS`
declaration with a positive integer exactly representable as Double. Omitted
units are typed unsupported for this profile, not invalid DEF generally. No
consumer default is inferred: the ordinary reader's historical 1000 differs
from the pinned OpenROAD v1 omitted-unit behavior of 100. Duplicate, malformed
or invalid declarations fail. Ordinary `read` and its default remain compatible.

Regular and special net geometry/connectivity clauses must be represented by the
existing AST and route/pin admission. SUBNET, VPIN, MUSTJOIN, SHIELDNET and other
unrepresented net clauses fail before a document is returned. Metadata-only
SOURCE/WEIGHT/ESTCAP/FREQUENCY/XTALK/ORIGINAL single values may be skipped without
changing geometry or connection inventory; they do not establish timing or
extraction authority. Existing route extension/via storage and unsupported route
checks remain authoritative. The strict path never interprets nested unsupported
clause coordinates as connections. It does not enlarge the underlying DEF grammar.

`Tests/DEFTests/DEFStrictSourceTests.swift` owns explicit units/literal/range,
missing/duplicate/malformed/domain refusal, exact connections/routes/extensions/
via orientation, geometry-bearing clause refusals, ordinary compatibility,
source byte admission and cancellation. Upper routed PEX consumers separately
validate LEF layer/via/terminal joins and complete extraction coverage.

DEFTests owns orientation semantics and format behavior. Native consumers separately
prove master, origin, pin, site and via preparation with the same standard transforms.
