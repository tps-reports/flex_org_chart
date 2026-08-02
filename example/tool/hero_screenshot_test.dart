// ignore_for_file: avoid_print
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart' show FontLoader, rootBundle;
import 'package:flutter_test/flutter_test.dart';

import 'package:flex_org_chart_example/main.dart';

/// Regenerates the README/pub.dev hero screenshot from the real demo app.
///
/// This lives under `tool/`, not `test/`, so a plain `flutter test` run
/// (the CI/publish gate) never executes it — screenshot generation is a
/// deliberate, on-demand step:
///
///   cd example && flutter test tool/hero_screenshot_test.dart
///
/// It renders the actual [DemoApp] widget tree — same code, same data, same
/// theme as `flutter run` — through a [RenderRepaintBoundary] and writes the
/// resulting PNG straight to `doc/screenshot.png`. This is a real capture of
/// the widget, not a hand-composed mockup.
///
/// A bare `flutter test` run can't reach any platform font (there's no
/// device/OS text-shaping backend in the headless test embedder), so
/// widgets normally render every glyph as a tofu box. [_loadRealFonts]
/// backs the two families this app actually uses — 'MaterialIcons' (the
/// action-button/expand-button icons) and 'Roboto' (Material's default text
/// family) — with real font bytes purely for this local render. Nothing
/// here is bundled into the package or committed: only the resulting PNG
/// is, and it never embeds font data.
void main() {
  testWidgets('generates doc/screenshot.png from the real demo app', (
    tester,
  ) async {
    // Font loading is real async I/O (a platform round-trip into the
    // engine); it must run via runAsync to escape the FakeAsync zone
    // `testWidgets` otherwise runs in, or the await never completes.
    await tester.runAsync(_loadRealFonts);

    const size = Size(1400, 900);
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final boundaryKey = GlobalKey();
    await tester.pumpWidget(
      RepaintBoundary(key: boundaryKey, child: const DemoApp()),
    );
    // Let the initial fit + any layout animation finish, then trigger the
    // highlight-path demo so the screenshot shows off highlighting too.
    await tester.pumpAndSettle();
    await tester.tap(find.text('Hedy Lamarr'));
    await tester.pumpAndSettle();

    final boundary =
        boundaryKey.currentContext!.findRenderObject() as RenderRepaintBoundary;
    final image = await tester.runAsync(
      () => boundary.toImage(pixelRatio: 2.0),
    );
    final bytes = await tester.runAsync(
      () => image!.toByteData(format: ui.ImageByteFormat.png),
    );

    final file = File('${Directory.current.path}/../doc/screenshot.png');
    file.parent.createSync(recursive: true);
    file.writeAsBytesSync(bytes!.buffer.asUint8List());
    print('Wrote ${file.path} (${bytes.lengthInBytes} bytes)');
  });
}

Future<void> _loadRealFonts() async {
  final icons = FontLoader('MaterialIcons')
    ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
  await icons.load();

  // Read a real system font file directly off disk (not through the asset
  // bundle, and never packaged) purely to back the 'Roboto' family for
  // this one local render.
  const systemFont = '/System/Library/Fonts/Supplemental/Arial.ttf';
  final fontFile = File(systemFont);
  if (fontFile.existsSync()) {
    final bytes = await fontFile.readAsBytes();
    final roboto = FontLoader('Roboto')
      ..addFont(Future.value(ByteData.view(bytes.buffer)));
    await roboto.load();
  }
}
