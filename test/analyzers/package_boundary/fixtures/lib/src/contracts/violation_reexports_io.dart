// Expected: 1 issue, severity blocker, line 7.
// A contracts file re-exports an adapter module — this leaks the forbidden
// dependency to anyone importing the contract.

import 'package:meta/meta.dart';

export 'package:fixture_pkg/src/adapters/foo/adapter.dart';

@immutable
class LeakyContract {
  const LeakyContract();
}
