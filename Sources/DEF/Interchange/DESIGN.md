# DEF Interchange

## Purpose and Scope

Own DEFDocument to LayoutIR conversion and standard orientation interpretation.
Parent: [DEF](../DESIGN.md). No children.

## Responsibilities and Boundaries

Map standard orientations to the existing IRTransform meaning: reflection about X
before counterclockwise rotation. Engines own transformed master-size bounds,
LEF ORIGIN adjustment, site compatibility and foundry rules.

## Related Designs

| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [DEF](../DESIGN.md) | parent | Typed document and orientation values | Standard interchange | Preserve source names and explicit mappings |
| [Package](../../../DESIGN.md) | depends on | LayoutIR geometry and unit scale | Common representation | Reflection precedes rotation |

## Architecture

```text
DEF orientation -> exact unit orthogonal IRTransform
IRTransform -> finite/unit/quarter-turn validation -> DEF orientation or typed error
```

## Contracts and Invariants

The [LEF/DEF 5.8 reference](https://coriolis.lip6.fr/doc/lefdef/lefdefref/DEFSyntax.html)
defines N=R0, S=R180, W=R90, E=R270, FN=MY, FS=MX, FW=MX90, FE=MY90.
Because IRTransform mirrors about X before rotation, FN uses mirrorX plus 180 degrees;
FS uses mirrorX plus zero degrees. FW and FE use 90 and 270 degrees respectively.
A semantic fixture checks these values independently of inverse conversion.

Inverse conversion admits finite unit magnification and exact quarter turns modulo
360. Fractional/non-quarter rotations, nonfinite angles and non-unit scales throw
`DEFIRConverterError.unrepresentableTransform`; they are not rounded or defaulted
into N/FN. `toDEFDocument` propagates this typed failure for geometry transforms.
Route conversion uses the NETS and SPECIALNETS routing-point rules in the same
reference. NETS omitted extensions mean half of the preferred LEF routing width;
SPECIALNETS omitted extensions mean zero. Explicit extensions are nonnegative DEF
DBU distances and are not scaled until a consuming geometry boundary. Each adjacent
coordinate pair is one wire segment, including at a bend. Conversion emits straight
IR paths so interior-point extensions are preserved without introducing miter area.
Regular default-width paths retain the existing width placeholder of one DBU; that
placeholder is not a physical width. The consumer must admit an exact preferred LEF
WIDTH before evaluating geometry, then apply `halfWidthExtend` symbolically.

| Source segment | IR guarantee | Failure |
|---|---|---|
| NETS, both extensions omitted | `halfWidthExtend` | Width qualification belongs to consumer |
| NETS, both explicit | `customExtension`, exact begin/end DBU | Negative extension rejected |
| NETS, one omitted and one explicit | No successful geometry | Typed unsupported: physical width required |
| SPECIALNETS | `flush` for zero/zero, otherwise `customExtension` | Width must be positive/even |

The bounded route profile accepts nonzero orthogonal segments and named via placements.
A single coordinate followed by a named via is a standalone `IRElement.via`, never
a zero-length `IRPath`. A terminal named via after a wire is also a separate placement.
All eight standard orientations are retained through the existing IRTransform contract.
The [ViaPlacement contract](../../LayoutIR/ViaPlacement/DESIGN.md) owns typed fields and
unresolved format-output admission. Standalone via point extensions are rejected.
45-degree styles, TAPER/TAPERRULE/STYLE/NONDEFAULTRULE, masks, virtual/rect geometry,
and an in-path via continuation require additional semantics and fail explicitly.
The text reader rejects unknown geometric tokens instead of skipping them. First
wildcard coordinates and zero-length segments fail. Inverse conversion derives the
endpoint extensions from IR geometry and emits equivalent straight DEF routes;
route provenance cannot override modified path geometry.

## Runtime Flows

Reader -> typed DEFDocument -> IR conversion. IR export validates a component/text
transform before appending the corresponding standard record. Failure returns no
successful document.

## State, Ownership, and Lifecycle

Conversion uses invocation-local value state. No shared cache or pointer exists.

## Failure, Concurrency, and Constraints

Orientation conversion is constant work. Validation occurs before integer conversion;
nonfinite and out-of-range Double angles cannot trap by conversion to Int.

## Verification and Change Impact

DEF orientation tests compare all eight transformations against the standard table,
verify inverse rotations including negative/full turns, and verify malformed transform
failure through both direct conversion and document export. Literal-byte route tests
check missing/explicit/zero/negative extensions, NEW boundaries, layer names, DBU
scales, and unsupported profiles. Independent straight-rectangle bounds check the
wire footprint, and DEF/IR/text roundtrips preserve segment shape. Recheck native process
geometry consumers when standard orientation or LayoutIR transform semantics change.
