// Fixture: presentation importing from domain — explicitly allowed (presentation
// has no `forbid_imports` entries against domain). The rule is asymmetric.
// Expected: 0 issues.

import 'package:sample_app/src/domain/foo_entity.dart';

class ValidImportsDomain {}
