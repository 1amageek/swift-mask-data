# Technology Unit Declarations

## Purpose and Scope

Own `IRTechUnitDeclarations`, format-neutral retained precision declarations.
Parent: [TechIR](../DESIGN.md). No children.

## Responsibilities and Boundaries

Retain optional declarations for time, capacitance, resistance, power, current,
voltage and frequency as independent values. Database distance resolution stays
in the owning library's `dbuPerMicron`, with independent
`hasDatabaseUnitsDeclaration` source presence. Source grammar and validation belong to
codecs; numerical models own physical unit interpretation and SI conversion.

## Related Designs

| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [TechIR](../DESIGN.md) | parent | Library value and serialization | Shared portable values | No host I/O |
| [LEF Codec](../../LEF/Codec/DESIGN.md) | used by | Named unit declarations | Exact optional precision facts | Factors are not blanket physical scaling |

## Architecture

```text
Source declarations -> codec validation -> IRTechUnitDeclarations
    -> library serialization / format projection -> consuming numerical model
```

## Contracts and Invariants

Each named field retains its raw declaration or absence. Values are Sendable,
Hashable and Codable with Standard Library ownership. Missing fields remain nil;
legacy library/document values without this record decode to an empty record.
The value record does not infer, round or apply numerical conversion factors.
Library declaration presence survives format projection and legacy decode defaults
to explicit stored precision; assembly-level inheritance belongs to consumers.

## Verification and Change Impact

[LEFUnitTests](../../../Tests/LEFTests/LEFUnitTests.swift) verifies standard source,
programmatic writer, JSON, legacy decode and bidirectional library projection.
Changes affect LEF and other consumers of IRTechLibrary; they must retain declarations.
