// Expected: 1 issue, severity blocker, line 6.
// Analyzers must not depend on adapters — adapters depend on analyzers via
// contracts, never the other way around.

import 'package:fixture_pkg/src/contracts/foo_contract.dart';
import 'package:fixture_pkg/src/adapters/foo/adapter.dart';

class FooAnalyzer {
  FooAnalyzer();
}
