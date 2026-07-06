/// Minimal geometry for the layout layer. No dart:ui here by design —
/// the layout engine must run without Flutter.
typedef Pt = ({double x, double y});

class LayoutRect {
  const LayoutRect(this.left, this.top, this.width, this.height);
  final double left, top, width, height;
  double get right => left + width;
  double get bottom => top + height;
  double get centerX => left + width / 2;
  double get centerY => top + height / 2;
}
