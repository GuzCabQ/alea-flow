// Fixture: buttons with visible content.
// Expected: 0 issues.
//
// Includes buttons whose `style:` is built with `ElevatedButton.styleFrom(...)`
// — a ButtonStyle factory, NOT a button. Its style-only args (backgroundColor,
// shape…) must never be mistaken for a content-less button (freya parity bug).

import 'package:flutter/material.dart';

class ButtonWithContent extends StatelessWidget {
  const ButtonWithContent({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        ElevatedButton(onPressed: () {}, child: const Text('Save')),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: () {},
          icon: const Icon(Icons.add),
          label: const Text('Add item'),
        ),
        const SizedBox(height: 8),
        IconButton(onPressed: () {}, icon: const Icon(Icons.close)),
        ElevatedButton(
          onPressed: () {},
          style: ElevatedButton.styleFrom(backgroundColor: Colors.blue),
          child: const Icon(Icons.star),
        ),
        ElevatedButton.icon(
          onPressed: () {},
          style: ElevatedButton.styleFrom(backgroundColor: Colors.blue),
          icon: const Icon(Icons.call),
          label: const Text('Call'),
        ),
      ],
    );
  }
}
