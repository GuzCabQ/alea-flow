// Expected: 0 issues.
// Adapters are the outer ring — they can import contracts and I/O freely.

import 'dart:io';

import 'package:fixture_pkg/src/contracts/foo_contract.dart';

class FooAdapter {
  FooAdapter();
  bool ping() => File('.').existsSync();
}
