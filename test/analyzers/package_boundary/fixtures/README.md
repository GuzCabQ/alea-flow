# Fixtures — PackageBoundaryAnalyzer

Synthetic project tree used by `analyzer_test.dart`. The fixture simulates a
library package called `fixture_pkg` with these internal layers:

- `lib/src/contracts/`     → pure contracts; must not import `dart:io` nor
                             anything from `adapters/`.
- `lib/src/matching/`      → pure math; must not import any I/O at all.
- `lib/src/analyzers/`     → analyzers; must not import from `adapters/`.
- `lib/src/adapters/`      → free to import everything else.

Files prefixed with `valid_` should produce zero issues. Files prefixed with
`violation_` should produce exactly one issue at the line declared in the
file's leading comment.

Real Dart code is not compiled — the analyzer only parses imports — so missing
type references in the bodies are intentional and harmless.
