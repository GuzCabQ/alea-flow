/// ALEA — Pure matching library.
///
/// Public, side-effect-free entry point for color distance (ΔE CIE2000),
/// set similarity, fuzzy string scoring, and numeric quantization. Importable
/// from any Dart context — including AOT-restricted ones — without dragging
/// `dart:io`, AST parsers, or filesystem access.
///
/// Purity is enforced by the `matching_purity` rule of
/// `alea/.alea.yaml::architecture.package_boundaries[]`, which is verified
/// in CI by `tool/check_alea_boundaries.dart`. Adding an export from outside
/// `lib/src/matching/` will fail that check.
library;

export 'src/matching/color_distance.dart';
export 'src/matching/fuzzy_score.dart';
export 'src/matching/jaccard.dart';
export 'src/matching/snap_to_steps.dart';
