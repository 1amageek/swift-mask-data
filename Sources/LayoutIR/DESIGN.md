# LayoutIR

## Purpose and Scope

Own format-neutral layout values, hierarchy references, units and explicit via placements.
Parent: [package](../../DESIGN.md). Child: [ViaPlacement](ViaPlacement/DESIGN.md).

## Responsibilities and Boundaries

Provide owned Sendable geometry and provenance. Technology binding, physical via-master
resolution, rule interpretation and electrical topology belong to consumers.

## Related Designs

| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [Package](../../DESIGN.md) | parent | Standard data boundary | Library composition | Codecs must preserve meaning or reject |
| [ViaPlacement](ViaPlacement/DESIGN.md) | child | Immutable `IRVia` | Named placement responsibility | Master geometry is not a wire |
| [DEF](../DEF/DESIGN.md) | used by | Layout values and units | Standard route projection | Exact orientation and source layers |
| [OASIS](../OASIS/DESIGN.md) | used by | Geometry and references | Binary interchange | Unresolved typed vias reject |

## Architecture

```text
IRLibrary(DBU) -> IRCell -> IRElement
                           -> polygon / wire / text / hierarchy reference
                           -> IRVia -> bound technology consumer
```

## Contracts and Invariants

Each element case represents one semantic responsibility. `IRVia` is a named
placement and cannot be represented as a degenerate wire. The ViaPlacement design
owns its field, transform and unresolved-output guarantees. Library unit scale uses
CircuiteFoundation's admitted DatabaseUnitScale; no new unit identity is introduced.

## Verification and Change Impact

LayoutIRTests prove value retention. DEF and codec tests prove actual semantic
conversion and rejection. Consumer geometry evidence belongs to LayoutIO and
ConductorCapture; changes to enum cases require those owners to recheck dispatch.
