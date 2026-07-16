# swift-mask-data goal status

## Baseline completed

- `CircuiteFoundation` is a local Swift Package Manager dependency of
  `LayoutIR`.
- `IRLibrary` owns `DatabaseUnitScale` directly without a duplicate unit type.
- GDSII and OASIS readers and writers validate unit metadata through the
  shared `DatabaseUnitScale` boundary and preserve typed, location-aware
  failures for invalid input.
- Canonical region boolean operations are exact, throwing, and have no silent
  approximate fallback.
- Standalone responsibilities and implementation-agent hand-off rules are
  documented.

## Verification

Run from this package directory:

```bash
swift build
swift test
```

The parent integration task records the complete test result after sibling
package migrations. Standard-format and foundry-corpus qualification remain
separate milestones.

## Next implementation work

1. Migrate consuming engines to Foundation artifact/provenance types at their
   output boundaries.
2. Add more malformed-input and exactness fixtures for every codec.
3. Keep geometry and format-specific behavior in this package while leaving
   orchestration to higher layers.
