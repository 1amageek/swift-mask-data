# ViaPlacement

## Purpose and Scope

Own immutable named via placements, separate from wires and hierarchy cell instances.
Parent: [LayoutIR](../DESIGN.md). No children.

## Responsibilities and Boundaries

`IRVia` retains a master name, origin in the library DBU, definition-local transform,
source routing-layer number and provenance properties. A placement contains no wire
vertices, width or fabricated footprint. Master geometry and process interpretation
belong to the consuming bound technology owner. Native LayoutIO must resolve exactly
one named via and retain its transformed definition geometry without adding a wire.

## Related Designs

| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [LayoutIR](../DESIGN.md) | parent | `IRElement.via` and library DBU | Typed value composition | A via is not an `IRPath` |
| [DEF Interchange](../../DEF/Interchange/DESIGN.md) | used by | Named placements and provenance | Source route interpretation | Source orientation and net identity remain exact |
| [LayoutIO](../../../../semiconductor-layout/Sources/LayoutIO/DESIGN.md) | used by | Bound master resolution | Physical via placement | Unknown or ambiguous masters fail before output |

## Architecture

```text
DEF named via -> IRVia(name, origin, transform, routeLayer, properties)
IRVia + bound technology -> LayoutVia -> individual transformed cut/landing geometry
IRVia without resolved master -> typed codec rejection, no serialized output
```

## Contracts and Invariants

All stored fields are immutable Sendable values. The containing library owns DBU
scale. The transform follows `IRTransform`: mirror about X before counterclockwise
rotation; translation is the separate origin. DEF admits only exact unit orthogonal
transforms and propagates the existing transform error for unrepresentable values.
`routeLayer` preserves the DEF declaration's routing layer; it does not name the cut
or expand master geometry. Source net/status/layer-name metadata is provenance and
cannot manufacture connectivity. DEF placements after a wire become a separate typed
via; their path carries no duplicated via placement.

GDSII/OASIS/CIF/DXF writers and LEF inverse conversion lack a bound via-master resolver.
Their current supported contract rejects any `IRElement.via` before serializing or
publishing output, including when earlier elements are valid. A future reference
encoding must preserve the resolved master and explicit placement role; cell-instance
coercion, unresolved reference success and geometry omission are not admitted.

## State, Ownership, and Lifecycle

Values own their name and provenance through Swift value storage. Consumers own the
resolved technology lifetime. No mutable shared state, borrowed pointer or cache exists.

## Failure, Concurrency, and Constraints

DEF text parsing validates nonnegative point extensions and standard orientations.
A standalone placement with a wire extension is outside the bounded profile and
fails explicitly. DEF inverse conversion rejects child-cell via placements before
publication until resolved hierarchy flattening can preserve their net provenance.
Missing/ambiguous masters and unsupported output representations
are typed failures; no empty geometry, default master or repeated endpoint is emitted.

## Verification and Change Impact

`DEFStandaloneViaTests` uses literal bytes from the actual native routing failure and
checks typed placement, all eight orientations, source units/layer/net and inverse text.
`ViaPlacementCodecTests` checks Codable retention and unsupported codecs return no data
or document. Native LayoutIO separately proves actual bound master footprints and
contacts. Changing fields invalidates DEF/codec and LayoutIO consumer assumptions;
compile success alone does not establish those geometry guarantees.
