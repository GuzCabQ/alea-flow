// Expected: 1 issue, severity blocker, line 6.
// Contracts must not depend on adapters — that would invert the architecture.

import 'package:meta/meta.dart';

import 'package:fixture_pkg/src/adapters/foo/adapter.dart';

@immutable
class WrongContract {
  const WrongContract();
}
