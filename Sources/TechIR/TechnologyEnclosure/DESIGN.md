# Technology Enclosure

## Purpose and Scope

Own exact layer enclosure declarations, the legacy inter-layer scalar rule, and
via enclosure values. Parent: [TechIR](../DESIGN.md). No children.

## Responsibilities and Boundaries

Retain adjacent-layer side and both opposing-side overhangs in microns. Codecs
own syntax; physical consumers own stack identity, geometry and rule application.
Legacy scalar inter-layer rules remain independent values with their existing
outer/inner-layer meanings. A cut-layer declaration cannot fabricate those layer
identities or collapse an asymmetric pair to a scalar minimum.

## Related Designs

| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [TechIR](../DESIGN.md) | Parent | Technology values | Portable value ownership | No DRC qualification |
| [TechnologyGrid](../TechnologyGrid/DESIGN.md) | Used by | Layer enclosures | Exact declaration array | Consumers must admit or refuse every retained rule |
| [LEF PhysicalSchema](../../LEF/PhysicalSchema/DESIGN.md) | Used by | Shared declaration type | LEFEnclosure compatibility alias | Legacy single view cannot represent directional alternatives |
| [LEF Codec](../../LEF/Codec/DESIGN.md) | Used by | Source/writer/projection | Validated standard subset | WIDTH/LENGTH/EXCEPTEXTRACUT remain unsupported |

## Architecture

```text
ENCLOSURE statements -> ordered IRTechLayerEnclosure array -> LEF / TechIR layer
    -> exact stack/side/geometry admission by consumers
```

## Contracts and Invariants

An optional side is above or below; absence applies to both adjacent routing
layers. `overhang1` applies to two opposing rectangle sides and `overhang2` to the
other two, rather than to fixed X/Y axes. Values retain their finite signed
micron amounts; geometry evaluation and feasibility belong to the consumer.
The source codec supports unqualified/ABOVE/BELOW pairs only. Repeated rules
remain ordered and retained, including alternatives; they are not overwritten.
For the supported no-WIDTH subset, applicable alternatives are OR choices, not
simultaneous requirements or last-wins assignments. No rule is invented when the
array is empty. [LEF 5.8](https://coriolis.lip6.fr/doc/lefdef/lefdefref/LEFSyntax.html)
owns these meanings.

LEF and TechIR layer arrays are the single source of enclosure facts. LEF's
legacy `enclosure` view returns a value only for exactly one unqualified rule.
Its setter replaces unqualified alternatives while preserving directional rules;
new callers edit `enclosures` for exact sequence changes. The initializer retains
its legacy enclosure argument by prepending it to the supplied array. Legacy
JSON's singular `enclosure` migrates into a one-element array; new JSON emits only
`enclosures`. Simultaneous old/new keys must agree exactly or decoding fails.
Missing legacy fields remain an empty array. The old `LEFEnclosure` name aliases
the same value type instead of maintaining a second physical schema.

LEF-to-TechIR projection retains the exact array and generates no legacy scalar
`IRTechLibrary.enclosureRules`: even a symmetric pair lacks exact adjacent
routing-layer identities at that old projection boundary. Existing scalar rule
values/API/JSON remain available without being synthesized from cut declarations.

## Verification and Change Impact

[LEFLayerEnclosureTests](../../../Tests/LEFTests/LEFLayerEnclosureTests.swift)
verifies source/writer/JSON/TechIR, repeated and directional pairs, signed finite
values, legacy migration, dual-key conflict and unsupported variants.
Native Physical ProcessGeometry's old `enclosure` reader and LayoutIO's scalar
rule projection require capability/application migration before dependency adoption.
The Xcircuite electrical standard-layout importer composes that LayoutIO path;
retention alone does not establish DRC or fixed-contact legality.
