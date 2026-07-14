# swift-mask-data design

## Purpose

The package is the standard-mask-data boundary for independently usable design
tools. It converts files into a stable intermediate representation and provides
geometry operations without knowing how a project is scheduled or approved.

## Layer responsibilities

| Layer | Owns | Does not own |
|---|---|---|
| `LayoutIR` | Format-neutral geometry, hierarchy references, properties, and units | Physical process-rule interpretation |
| Format codecs | Parsing and serialization of one standard format | Generic project state |
| `TechIR` | Format-neutral technology records | Foundry qualification decisions |
| `MaskGeometry` | Polygon boolean/sizing/connectivity and geometry checks | Electrical netlist semantics |

## CircuiteFoundation contract

`CircuiteFoundation` is a direct dependency of `LayoutIR`:

- `DatabaseUnitScale` validates positive finite database-unit scales.
- `IRUnits(scale:)` and `IRUnits.validatedScale` provide an explicit bridge
  between file-format units and the shared scale type.
- Artifact, provenance, diagnostic, and engine protocols remain available to
  consuming packages; this library does not wrap codec calls in a generic
  engine envelope.

```mermaid
flowchart TD
  Bytes["format bytes"] --> Reader["format reader"]
  Reader --> IR["LayoutIR"]
  IR --> Geometry["MaskGeometry"]
  IR --> Writer["format writer"]
  Foundation["CircuiteFoundation\nDatabaseUnitScale"] --> IR
  IR --> Layout["semiconductor-layout / engines"]
```

## Exactness policy

Legacy region boolean methods may use the general geometry processor for
compatibility. The `andChecked`, `orChecked`, `xorChecked`, and `notChecked`
methods use only the exact rectilinear kernel and throw
`RegionBooleanError.unsupportedNonManhattanGeometry` otherwise. Consumers must
select the checked API for signoff paths.

## Extension point for implementation agents

Agents adding a new format should add a codec target/file set, map it to
`LayoutIR`, preserve typed parse/write errors, and add round-trip fixtures. They
should not add project/run state or duplicate `DatabaseUnitScale` validation.
