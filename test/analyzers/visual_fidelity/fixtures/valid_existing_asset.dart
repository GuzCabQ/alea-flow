// Fixture: asset that exists on disk in the fixture project root.
// Expected: 0 issues.
// The fixture project root for this test is `test/analyzers/visual_fidelity/fixtures/`,
// and `assets/exists.png` is materialized there (see analyzer_test.dart setUp).

import 'package:flutter/widgets.dart';

class ExistingAsset extends StatelessWidget {
  const ExistingAsset({super.key});

  @override
  Widget build(BuildContext context) {
    return Image.asset('assets/exists.png', fit: BoxFit.cover);
  }
}
