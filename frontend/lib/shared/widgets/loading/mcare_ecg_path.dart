import 'dart:ui';

/// Canonical mCare ECG lifeline geometry.
///
/// Source of truth is the splash/wordmark SVG:
/// `M0 14 H19 L21 13 L23 14 H29 L30 17 L33 1 L37 23 L38 14 H44 H108`
/// in a 118×24 viewBox.
///
/// Every loading state in the app traces this same path, so a spinner reads as
/// the wordmark's own lifeline rather than a generic Material spinner.
class McareEcgPath {
  McareEcgPath._();

  /// viewBox dimensions the raw control points are expressed in.
  static const double viewWidth = 118;
  static const double viewHeight = 24;

  /// Flat-line y in view units. The QRS complex departs from here.
  static const double baselineY = 14;

  /// Largest departure from [baselineY] in the path (the S-wave at y=23).
  static const double maxDeviation = 13;

  /// Control points in view units, in draw order.
  static const List<Offset> _points = <Offset>[
    Offset(0, 14),
    Offset(19, 14),
    Offset(21, 13), // P wave
    Offset(23, 14),
    Offset(29, 14),
    Offset(30, 17), // Q
    Offset(33, 1), // R — the tall spike
    Offset(37, 23), // S
    Offset(38, 14),
    Offset(44, 14),
    Offset(108, 14),
  ];

  /// Builds the lifeline scaled proportionally into [size].
  static Path build(Size size) {
    final sx = size.width / viewWidth;
    final sy = size.height / viewHeight;
    final path = Path()..moveTo(_points.first.dx * sx, _points.first.dy * sy);
    for (var i = 1; i < _points.length; i++) {
      path.lineTo(_points[i].dx * sx, _points[i].dy * sy);
    }
    return path;
  }

  /// Baseline y in pixels for a box of [height].
  static double baselineFor(double height) => height * (baselineY / viewHeight);

  /// How far a point at [dy] sits from the baseline, normalised 0..1.
  /// Used to detect when the travelling head is riding the QRS spike.
  static double beatIntensity(double dy, double height) {
    final deviation = (dy - baselineFor(height)).abs();
    final max = height * (maxDeviation / viewHeight);
    if (max <= 0) return 0;
    return (deviation / max).clamp(0.0, 1.0);
  }
}
