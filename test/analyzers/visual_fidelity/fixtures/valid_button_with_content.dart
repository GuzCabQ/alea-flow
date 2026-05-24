// Fixture: buttons with visible content.
// Expected: 0 issues.

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
      ],
    );
  }
}
