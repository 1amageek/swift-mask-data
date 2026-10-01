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
Other existing document/metadata conversion behavior is unchanged by this boundary.

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
failure through both direct conversion and document export. Recheck native process
geometry consumers when standard orientation or LayoutIR transform semantics change.
