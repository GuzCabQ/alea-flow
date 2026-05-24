// Fixture: a synthetic project that uses a different class name to verify
// that the adapter is fully config-driven.

// ignore_for_file: uri_does_not_exist
import 'package:flutter/material.dart';

class Palette {
  static const Color primary = Color(0xFF0066CC);
  static const Color onPrimary = Color(0xFFFFFFFF);
  static const Color background = Color(0xFFF7F8FA);
}

// This class must NOT be picked up — only the configured `color_class` is
// scanned.
class IgnoredColors {
  static const Color shouldNotAppear = Color(0xFF000000);
}
