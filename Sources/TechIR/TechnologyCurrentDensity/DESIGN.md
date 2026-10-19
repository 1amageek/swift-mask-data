# Technology Current Density

## Purpose and Scope

Own scalar electrical current-density declarations. Parent: [TechIR](../DESIGN.md).
No children.

## Responsibilities and Boundaries

Retain DC average and AC average, peak and RMS limits with their physical units.
Codecs own source spelling/validation. Electrical signoff owns waveform statistics,
operating conditions, source/profile reconciliation and current-limit evaluation.
Geometric placement/routing/DRC does not acquire electrical qualification from
these declarations, and their retention alone does not block geometric legality.

## Related Designs

| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [TechIR](../DESIGN.md) | Parent | Typed technology values | Portable retained facts | No electrical verdict |
| [TechnologyGrid](../TechnologyGrid/DESIGN.md) | Used by | Layer current limits | Unit-bearing values | Absence is not an unlimited-current guarantee |
| [LEF Codec](../../LEF/Codec/DESIGN.md) | Used by | Scalar source grammar | Standard interpretation | Tables remain unsupported |
| [Electrical topology](../../../../ElectricalSignoffEngine/Sources/ElectricalSignoffCore/TopologyExtraction/DESIGN.md) | Used by | Current-limit interpretation boundary | Owns actual electrical evaluation | Geometry success and electrical qualification are distinct |

## Architecture

```text
LEF scalar current statement -> kind + unit-bearing quantity -> layer facts
    -> electrical profile / waveform / geometry evaluation by electrical signoff
```

## Contracts and Invariants

`IRTechCurrentDensityLimit` distinguishes dcAverage, acAverage, acPeak and acRMS.
Its quantity is milliamperes per micron for ROUTING and milliamperes per square
micron for CUT. Routing thickness is implicit in the per-width declaration;
the codec does not multiply/divide by a guessed thickness or cut area.
Magnitude remains the source scalar, independent of CURRENT unit precision.
Finite nonnegative values are supported, and each kind occurs at most once per
layer. Different AC classes and DC average can coexist. Statement order is retained.
No frequency/width/cut-area table, operating temperature or waveform assumption
is fabricated. Missing legacy fields decode to an empty array.

The LEF 5.8 [CUT AC](https://coriolis.lip6.fr/doc/lefdef/lefdefref/LEFSyntax.html#CutACCurrentDensityDef)
and [CUT DC](https://coriolis.lip6.fr/doc/lefdef/lefdefref/LEFSyntax.html#CutDCCurrentDensityDef)
sections define scalar cut limits in mA/um^2. The
[ROUTING AC](https://coriolis.lip6.fr/doc/lefdef/lefdefref/LEFSyntax.html#RoutingACCurrentDensity)
and [ROUTING DC](https://coriolis.lip6.fr/doc/lefdef/lefdefref/LEFSyntax.html#RoutingDCCurrentDensity)
sections define routing limits in mA/um.
Original Sky130 cut comments describe mA per via instead, while the numeric
statement has standard per-area semantics. Raw source files and their hashes are
retained as evidence; comments do not alter the codec's unit authority. The
source/provider electrical interpretation remains unresolved for qualification
or current-limit use. In particular 0.36 remains 0.36 mA/um^2 in the codec and is
not renormalized into a per-via current. A 90 C comment does not create a verified
operating-condition profile. This discrepancy does not invalidate independent
geometric enclosure/routing checks.

All declarations are owned Sendable/Codable values without shared mutable state.

## Verification and Change Impact

[LEFLayerCurrentDensityTests](../../../Tests/LEFTests/LEFLayerCurrentDensityTests.swift)
verifies all kinds/units, source/writer/JSON/TechIR, absence, precision independence,
wrong contexts/units/duplicates and unsupported tables. Unchanged actual PDK
prefixes through END mcon and separately extracted exact met1 scalar statements
prove retention only. At the current-density sprint boundary, met1 MINENCLOSEDAREA was refused; fragments
do not establish full met1 intake. Full originals must explicitly identify their next
unsupported grammar. Electrical consumers must reconcile source/profile units
and verify actual electrical conditions before using these limits for qualification.
