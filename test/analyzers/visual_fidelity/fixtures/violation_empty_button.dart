// Fixture: buttons with no visible content.
// Expected: 2 issues (lines 14, 19), severity blocker.

import 'package:flutter/material.dart';

class EmptyButton extends StatelessWidget {
  const EmptyButton({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        ElevatedButton(
          onPressed: () {},
          child: const SizedBox(), // line 14 — blocker: no Text/Icon/Image
        ),
        const SizedBox(height: 8),
        TextButton(
          onPressed: () {},
          child: Container(
            width: 32,
            height: 32,
            color: const Color(0xFFFF0000),
          ), // line 19 — blocker
        ),
      ],
    );
  }
}
