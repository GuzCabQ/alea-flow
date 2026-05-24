// Fixture: domain file that imports presentation via a relative path (forbidden).
// Tests the relative-import canonicalization path.
// Expected: 1 issue, severity blocker, line 6.

import 'dart:async';
import '../presentation/foo_page.dart';

class ViolationImportsPresentationRelative {
  Future<void> work() async {}
}
