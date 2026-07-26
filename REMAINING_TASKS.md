# swift-mask-data Remaining Tasks

Updated: 2026-07-26

The canonical format readers, writers, units, strict failures, and exact region
operations are implemented. Remaining work is corpus breadth and consumer
alignment.

## Remaining tasks

| ID | Priority | Owner | Task | Exit criteria |
|---|---|---|---|---|
| SMD-W1 | P2 | Workspace integration | Keep consuming engines aligned with the Foundation artifact and provenance boundary emitted by this package. | Every active consumer retains canonical `ArtifactReference` and provenance values without introducing a duplicate mask-artifact schema. |

## External prerequisites

Foundry-scale qualification and process acceptance are ToolQualification and
flow-policy inputs. They are not format-parser success states.

## External P1 prerequisite

| Former ID | Owner | Required evidence |
|---|---|---|
| SMD-1 | Independent format-corpus workflow | Lawfully retained files from multiple independent GDSII, OASIS, LEF, DEF, CIF, and DXF producers, including malformed and unsupported-loss cases. Writer-generated round trips cannot substitute for independent producer evidence, and the library must not fabricate that corpus. |

## Evidence reviewed

- `GOAL_STATUS.md`, especially `Next implementation work`
- `README.md`
- `Sources` incomplete-implementation marker scan
