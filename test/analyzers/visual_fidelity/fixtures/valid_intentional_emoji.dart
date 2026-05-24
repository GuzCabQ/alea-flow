// Fixture: emoji embedded in real text content (intentional use, not icon).
// Expected: 0 issues — emoji embedded in sentences is not flagged.

import 'package:flutter/widgets.dart';

class IntentionalEmoji extends StatelessWidget {
  const IntentionalEmoji({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: const [
        Text('Order placed! 🎉 We will notify you soon.'),
        Text('Welcome to the app 👋'),
        Text('Status: completed ✓'),
      ],
    );
  }
}
