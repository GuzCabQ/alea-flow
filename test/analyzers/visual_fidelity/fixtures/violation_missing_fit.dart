// Fixture: image widgets without fit:.
// Expected: 3 issues (Image.asset, SvgPicture.asset, Lottie.asset), severity critical.

import 'package:flutter/widgets.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:lottie/lottie.dart';

class MissingFit extends StatelessWidget {
  const MissingFit({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Image.asset('assets/logo.png'), // line 14 — critical
        SvgPicture.asset('assets/icon.svg'), // line 15 — critical
        Lottie.asset('assets/animation.json'), // line 16 — critical
      ],
    );
  }
}
