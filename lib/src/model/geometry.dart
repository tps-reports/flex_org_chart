/// Minimal geometry for the layout layer. No dart:ui here by design —
/// the layout engine must run without Flutter.
typedef Pt = ({double x, double y});

/// An axis-aligned rectangle in layout space (top-left origin, `y` grows
/// downward), used for node bounds, chart bounds, and viewport math.
class LayoutRect {
  /// Creates a rectangle from its top-left corner and size.
  const LayoutRect(this.left, this.top, this.width, this.height);

  /// X coordinate of the left edge.
  final double left;

  /// Y coordinate of the top edge.
  final double top;

  /// Extent along the X axis.
  final double width;

  /// Extent along the Y axis.
  final double height;

  /// X coordinate of the right edge (`left + width`).
  double get right => left + width;

  /// Y coordinate of the bottom edge (`top + height`).
  double get bottom => top + height;

  /// X coordinate of the horizontal center.
  double get centerX => left + width / 2;

  /// Y coordinate of the vertical center.
  double get centerY => top + height / 2;
}
