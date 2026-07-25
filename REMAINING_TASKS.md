# swift-mask-data Remaining Tasks

Updated: 2026-07-26

The canonical format readers, writers, units, strict failures, and exact region
operations are implemented. Remaining work is corpus breadth and consumer
alignment.

## Remaining tasks

| ID | Priority | Owner | Task | Exit criteria |
|---|---|---|---|---|
| SMD-1 | P1 | swift-mask-data | Expand independent third-party producer corpora for GDSII, OASIS, LEF, DEF, CIF, and DXF. | Retained fixtures cover multiple independent producers, malformed inputs, unsupported-loss cases, and deterministic success/failure expectations without relying on writer-generated round trips. |
| SMD-W1 | P2 | Workspace integration | Keep consuming engines aligned with the Foundation artifact and provenance boundary emitted by this package. | Every active consumer retains canonical `ArtifactReference` and provenance values without introducing a duplicate mask-artifact schema. |

## External prerequisites

Foundry-scale qualification and process acceptance are ToolQualification and
flow-policy inputs. They are not format-parser success states.

## Evidence reviewed

- `GOAL_STATUS.md`, especially `Next implementation work`
- `README.md`
- `Sources` incomplete-implementation marker scan
