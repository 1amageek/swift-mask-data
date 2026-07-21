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
- CIF, DXF, and LEF decoding is strict by default. Malformed commands, lexical
  errors, invalid numbers, unterminated structures, and transforms that cannot
  be represented exactly produce typed errors instead of partial documents.
- CIF and DXF writers reject geometry, metadata, and transforms that their
  target formats cannot preserve exactly.
- Independent fixed fixtures cover GDSII, OASIS, LEF, DEF, CIF, and DXF reader
  semantics without relying on a writer-generated round trip.
- Standalone responsibilities and implementation-agent hand-off rules are
  documented.

## Verification

Run from this package directory:

```bash
perl -e 'alarm shift; exec @ARGV' 120 xcodebuild test \
  -scheme swift-mask-data-Package \
  -destination 'platform=macOS'
```

The parent integration task records the complete test result after sibling
package migrations. Standard-format and foundry-corpus qualification remain
separate milestones.

## Next implementation work

1. Migrate consuming engines to Foundation artifact/provenance types at their
   output boundaries.
2. Expand third-party producer corpora while retaining the independent minimal
   fixtures as the deterministic baseline.
3. Keep geometry and format-specific behavior in this package while leaving
   orchestration to higher layers.
