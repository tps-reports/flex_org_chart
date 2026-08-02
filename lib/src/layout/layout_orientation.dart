import '../model/geometry.dart';

/// The direction an org chart grows in, controlling both which screen axis
/// depth flows along and where the root is anchored.
enum ChartLayout {
  /// Root at the top, children flowing downward (the conventional org
  /// chart orientation).
  top,

  /// Root at the bottom, children flowing upward.
  bottom,

  /// Root at the left, children flowing rightward.
  left,

  /// Root at the right, children flowing leftward.
  right,
}

/// Maps a node's top-space layout position (centerX, topY, w, h)
/// into screen space for the requested layout direction.
LayoutRect orient(
  ChartLayout layout,
  double centerX,
  double topY,
  double w,
  double h,
  double totalDepthExtent,
) {
  switch (layout) {
    case ChartLayout.top:
      return LayoutRect(centerX - w / 2, topY, w, h);
    case ChartLayout.bottom:
      // mirror vertically within the total depth extent
      return LayoutRect(centerX - w / 2, totalDepthExtent - topY - h, w, h);
    case ChartLayout.left:
      // depth flows rightward; breadth becomes vertical
      return LayoutRect(topY, centerX - h / 2, w, h);
    case ChartLayout.right:
      return LayoutRect(totalDepthExtent - topY - w, centerX - h / 2, w, h);
  }
}
