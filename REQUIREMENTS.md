# swift-mask-data requirements

## Required baseline

- Build with Swift 6.3+ on macOS 26+.
- Keep `LayoutIR` as the canonical format-neutral interchange model.
- Preserve standard format data that the IR can represent.
- Keep codecs deterministic and public values `Sendable`/`Codable`.
- Fail explicitly on malformed input and unsupported exact geometry.
- Validate database-unit scales through `CircuiteFoundation.DatabaseUnitScale`
  at package boundaries.

## Foundation integration requirements

| Requirement | Acceptance condition |
|---|---|
| Unit ownership | `IRLibrary` stores `DatabaseUnitScale` directly and raw scales are validated before construction |
| Dependency direction | Only domain targets depend on Foundation; Foundation never depends on codecs |
| Exactness boundary | Canonical throwing boolean APIs never fall back to approximate geometry |
| Consumer interoperability | Layout IR remains independent of `semiconductor-layout` |

## Explicit non-goals

- Project manifests, run scheduling, approval workflows, or Agent orchestration.
- Electrical netlist extraction or LVS policy.
- Foundry-specific DRC qualification claims.
- A replacement for the shared Foundation vocabulary.

## Agent hand-off definition

The package is ready for format/geometry implementation agents when it builds,
focused round-trip and safety tests pass, and each new codec documents its IR
mapping, unsupported cases, and typed failure behavior.
