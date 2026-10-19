# Technology Properties

## Purpose and Scope

Own retained property declaration and typed assignment facts, and layer subtypes. Parent: [TechIR](../DESIGN.md). No children.

## Responsibilities and Boundaries

Retain object class, property name, declared scalar type, optional range and
library value. Values retain source numeric spelling; codecs validate grammar.
Consumers own process-rule capability. IRTechPropertyAssignment retains a name and typed scalar value; integer and real values keep lexical spelling. IRTechLayerSubtype represents format-neutral classification, while codecs own source spelling and base-type validation.

## Related Designs

| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [TechIR](../DESIGN.md) | Parent | Library declarations | Format-neutral storage | Not physical rule admission |
| [LEF Codec](../../LEF/Codec/DESIGN.md) | Used by | Typed declaration facts | Standard source validation | Unknown assigned rules remain unsupported |

## Architecture

```text
LEF declaration codec -> IRTechPropertyDefinition -> library serialization/projection
```

## Contracts and Invariants

Object types are LIBRARY, LAYER, MACRO, NONDEFAULTRULE, PIN, VIA and VIARULE.
Types are INTEGER, REAL and STRING. Numeric range endpoints retain lexical form;
values on definitions belong to LIBRARY only. No default is invented. Missing
legacy declarations decode as an empty list. Declaration presence does not apply
or qualify a property-based process rule. Layer assignments default empty and subtype defaults absent in legacy serialized values. Subtype is a checked projection of a recognized source assignment, never an inferred classification from a layer name.

## Verification and Change Impact

[LEFPropertyDefinitionTests](../../../Tests/LEFTests/LEFPropertyDefinitionTests.swift)
verifies source, writer, JSON, TechIR projection and invalid declarations.
Changes require rechecking LEF codec and exact physical intake consumers.
