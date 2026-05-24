// ignore_for_file: uri_does_not_exist, undefined_class
// A widget recognized by its base class only — the class name doesn't carry
// any of the configured suffixes.

import 'package:flutter/material.dart';

class LoadingOverlay extends StatelessWidget {
  const LoadingOverlay({super.key});

  @override
  Widget build(BuildContext context) {
    return Center(child: CircularProgressIndicator(color: StyleColors.brand60));
  }
}
