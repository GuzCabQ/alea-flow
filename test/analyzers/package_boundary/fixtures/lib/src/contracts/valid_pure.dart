// Expected: 0 issues.
// A pure contract that only depends on package:meta — allowed.

import 'package:meta/meta.dart';

@immutable
class FooContract {
  const FooContract();
}
