// Fixture: emoji used as Text content (icon substitution).
// Expected when NDS source != figma: 2 issues (lines 11, 12), severity major.
// Expected when NDS source == figma: 2 issues, severity critical.
// Line 13's Text ("Great job!") is NOT flagged — has actual text content.

import 'package:flutter/widgets.dart';

class EmojiAsIcon extends StatelessWidget {
  const EmojiAsIcon({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: const [
        Text('🎉'), // line 14 — flagged
        Text('📋'), // line 15 — flagged
        Text('Great job!'), // line 16 — NOT flagged (has real text)
        Text(
          'Welcome 👋',
        ), // line 17 — NOT flagged (mixed content, length > 4 visible)
      ],
    );
  }
}
