// Fixture: a representative StyleColors class with five known tokens plus
// a non-resolvable alias the adapter must skip.

// Intentionally unresolved import — the AST parser does not require it to be
// resolvable; the test only exercises syntactic parsing.
// ignore_for_file: uri_does_not_exist

import 'package:flutter/material.dart';

class StyleColors {
  // Hex form — 5 entries that the test expects to be returned verbatim.
  static const Color brand60 = Color(0xFFDA1884);
  static const Color brand40 = Color(0xFF4A0E2B);
  static const Color brand20 = Color(0xFFFCEDF6);
  static const Color secondary = Color(0xFFE0F5F5);
  static const Color overlay = Color.fromARGB(0x80, 0x00, 0x00, 0x00);

  // Alias — adapter must skip (no AST literal it can resolve).
  static const Color brand60Alias = brand60;

  // Not a Color field — adapter must skip.
  static const double radius = 8;

  // Non-static field — adapter must skip.
  final Color instanceColor = const Color(0xFF000000);
}
