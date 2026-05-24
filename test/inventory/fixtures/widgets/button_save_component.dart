// ignore_for_file: uri_does_not_exist, undefined_class, missing_required_argument
import 'package:flutter/material.dart';

class ButtonSaveComponent extends StatelessWidget {
  final VoidCallback onPressed;
  final String label;

  const ButtonSaveComponent({
    super.key,
    required this.onPressed,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return ElevatedButton(
      onPressed: onPressed,
      style: ElevatedButton.styleFrom(backgroundColor: StyleColors.brand60),
      child: Text(label, style: StyleFonts.body2),
    );
  }
}
