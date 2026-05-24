// ignore_for_file: uri_does_not_exist, undefined_class
import 'package:flutter/material.dart';

class TextFieldInput extends StatefulWidget {
  final String label;

  const TextFieldInput({super.key, required this.label});

  @override
  State<TextFieldInput> createState() => _TextFieldInputState();
}

class _TextFieldInputState extends State<TextFieldInput> {
  @override
  Widget build(BuildContext context) {
    return TextField(
      decoration: InputDecoration(
        labelText: widget.label,
        labelStyle: StyleFonts.caption,
        focusColor: StyleColors.secondary,
      ),
    );
  }
}
