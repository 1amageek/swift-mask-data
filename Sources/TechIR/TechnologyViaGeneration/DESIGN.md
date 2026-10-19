# Technology Via Generation

## Purpose and Scope

Own exact format-neutral via-generation formula facts. Parent:
[TechIR](../DESIGN.md). No children. This is not a generated via instance or a
geometry generator.

## Responsibilities and Boundaries

Retain the actual supported LEF 5.8 VIARULE GENERATE profile independently of
codec and process policy. Existing IRTechViaDef describes instantiated vias;
these formulas are never projected into that type or synthesized into rectangles.

## Related Designs

| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [TechIR](../DESIGN.md) | Parent | Library values | Owns ordered viaGenerationRules | Legacy absence is empty |
| [LEF Codec](../../LEF/Codec/DESIGN.md#via-generation-formulas) | Used by | Strict source/writer/projection | Owns supported grammar and validation | Does not grant process admission |
| [Native ProcessGeometry](../../../../PhysicalDesignEngine/Sources/PhysicalDesignCore/ProcessGeometry/DESIGN.md) | Used by | Process master materialization | Owns actual generated geometry | Must gate these formulas before dependency adoption |
| [LayoutIO](../../../../semiconductor-layout/Sources/LayoutIO/DESIGN.md) | Used by | Technology import | Owns editor technology conversion | Existing instantiated via conversion cannot represent formulas |

## Architecture

```mermaid
flowchart LR
  Source[VIARULE GENERATE] --> Codec[LEF codec]
  Codec --> Rule[IRTechViaGenerationRule]
  Rule --> Library[IRTechLibrary.viaGenerationRules]
  Rule --> Writer[Validated LEF emission]
  Library --> Consumer[Consumer admission and generation]
```

## Contracts and Invariants

One rule retains its name, ordered two routing-layer records with exact opposing
side enclosure pairs, cut-layer name, original cut rectangle coordinates, and
explicit X/Y center-to-center cut spacing. Coordinates, enclosure and spacing
are microns independent of DATABASE precision. Spacing is not edge-to-edge gap.
Routing record order does not invent bottom/top stack identities. Enclosure pair
orientation is not fixed to X/Y: generation chooses the direction maximizing cuts.
The cut rectangle location is retained, including a nonzero offset.

The supported profile contains exactly two distinct ROUTING names and one
distinct CUT name declared unambiguously by the source library. Both enclosure
components are finite signed values; rectangle coordinates are finite with
positive extents; center spacing components are finite positive. No integer-grid
rounding or legality inference occurs. Rules are ordered; duplicate rule names
are refused, while a fixed VIA may share a rule name in its separate namespace.
The name DEFAULT is reserved. Non-GENERATE rules and DEFAULT/WIDTH/RESISTANCE/
PROPERTY/obsolete DIRECTION variants remain explicit unsupported source failures.

Roots retain the same owned Sendable/Codable records. Legacy roots without the
array decode empty. Invalid raw JSON and nonthrowing reverse conversion preserve
facts for validated writer refusal rather than fabricating a legal rule.

## Verification and Change Impact

[LEFViaGenerationRuleTests](../../../Tests/LEFTests/LEFViaGenerationRuleTests.swift)
owns successful source/writer/JSON/TechIR retention and invalid boundary behavior.
Actual unchanged Sky130 three-corner inputs each contain 25 formulas and 25
explicit fixed VIAs; full source is accepted and round-trips under this profile.
No next unsupported command was observed in those three files. This codec
acceptance alone does not establish manufacturing support. Native and Layout consumers must explicitly admit or
refuse nonempty viaGenerationRules before normal dependency adoption. Correct
materialization additionally owns stack topology, enclosure alternatives and cut
spacing overrides; this value owner does not approximate those algorithms.
