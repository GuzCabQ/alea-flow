// Fixture: domain file that imports from package:flutter (forbidden — domain must be pure Dart).
// Expected: 1 issue, severity blocker, line 4.

import 'package:flutter/widgets.dart';

class ViolationImportsFlutter {}
