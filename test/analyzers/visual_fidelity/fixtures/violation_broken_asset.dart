// Fixture: asset paths that don't exist on disk, with no TODO escape hatch.
// Expected: 3 issues (lines 14, 15, 16), severity critical.
// Line 19's call has a TODO comment within 3 lines — NOT flagged.

import 'package:flutter/widgets.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:lottie/lottie.dart';

class BrokenAsset extends StatelessWidget {
  const BrokenAsset({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Image.asset(
          'assets/missing.png',
          fit: BoxFit.cover,
        ), // line 16 — critical
        SvgPicture.asset(
          'assets/gone.svg',
          fit: BoxFit.contain,
        ), // line 17 — critical
        Lottie.asset(
          'assets/lost.json',
          fit: BoxFit.contain,
        ), // line 18 — critical
        // TODO: asset missing — replace once design exports the icon.
        Image.asset(
          'assets/intentional_todo.png',
          fit: BoxFit.cover,
        ), // line 21 — NOT flagged
      ],
    );
  }
}
