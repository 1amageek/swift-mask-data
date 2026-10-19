# Technology Antenna

## Purpose and Scope

Own typed ordered antenna declarations and the existing unqualified legacy ratio
record. Parent: [TechIR](../DESIGN.md). No children.

## Responsibilities and Boundaries

Retain oxide model switches and diffusion-dependent area or side-area ratio laws.
Technology codecs own grammar validation; physical engines own shape/net/gate/
diffusion measurement, oxide selection, evaluation and manufacturing admission.
The existing `IRTechAntennaRule(layerName,maxRatio)` is an unqualified legacy
value. It cannot represent oxide scope, area basis or a diffusion-dependent law,
and is never synthesized from or substituted for the retained declarations.

## Related Designs

| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [TechIR](../DESIGN.md) | Parent | Layer technology values | Independent value ownership | No process qualification |
| [TechnologyGrid](../TechnologyGrid/DESIGN.md) | Used by | Layer antenna statements | Ordered retained facts | Empty legacy field means absent source declarations |
| [LEF Codec](../../LEF/Codec/DESIGN.md) | Used by | Typed antenna values | Source grammar and validation | Unsupported commands remain explicit failures |

## Architecture

```text
source model / ratio sequence -> typed ordered declarations -> layer
    -> consumer oxide-scoped measurement and rule admission
```

## Contracts and Invariants

`IRTechAntennaStatement` retains model switches and ratio statements in source
order. Oxides are 1 through 4. Each new layer begins in oxide1; a model switch
applies to following statements until the next switch. Repeated statements remain
retained; the last ratio of a given kind within an oxide defines its effective
law. No second resolved copy is stored and explicit model absence remains absent.

`diffusionArea` uses metal area for routing and cut area for cut layers;
`diffusionSideArea` uses routing metal sidewall area only. Both limit the ratio
for a conductor connected to diffusion. Scalar ratios and piecewise-linear laws
remain distinguishable. PWL points retain diffusion area in square microns and
unitless ratio. Scalar values and all PWL coordinates are finite, nonnegative
and within the reference grammar's signed 64-bit numeric magnitude. PWL requires
at least two points with strictly increasing diffusion area. Ratio ordinates may increase, remain equal
or decrease; the standard requires ascending diffusion inputs, not ratio outputs.
Linear interpolation belongs to the rule's mathematical meaning; extrapolation
and actual process evaluation are not invented at the codec boundary.

These contracts come from [LEF 5.8](https://coriolis.lip6.fr/doc/lefdef/lefdefref/LEFSyntax.html).
The Cadence 5.8 [reference parser grammar](https://github.com/The-OpenROAD-Project/OpenROAD/blob/a93f559065b168702a07c3d9053e11744a71bb52/src/odb/src/lef/lef/lef.y)
uses double-valued NUMBER for scalar ratios and PWL axes; fractional ratio
ordinates in actual PDK data are retained without integer rounding.

All values are owned Sendable/Codable values with no shared mutable state.
Legacy layers decode absent statements as an empty array. No threshold, model
switch or independent numerical result is fabricated from this absence.

## Verification and Change Impact

[LEFLayerAntennaTests](../../../Tests/LEFTests/LEFLayerAntennaTests.swift)
verifies scalar/PWL, scope/order/repetition, layer context, invalid inputs,
writer/projection parity, JSON/legacy behavior and unchanged actual-source intake.
Consumers must reject retained antenna declarations until their measurement and
rule-evaluation contracts implement the source law; codec success grants no pass.
