// Fixture: image widgets with fit: declared.
// Expected: 0 issues.

import 'package:flutter/widgets.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:lottie/lottie.dart';

class WithFit extends StatelessWidget {
  const WithFit({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Image.asset('assets/logo.png', fit: BoxFit.cover),
        SvgPicture.asset('assets/icon.svg', fit: BoxFit.contain),
        Lottie.asset('assets/animation.json', fit: BoxFit.contain),
      ],
    );
  }
}
