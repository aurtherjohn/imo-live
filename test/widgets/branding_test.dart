import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:imo_live/app/theme/app_theme.dart';
import 'package:imo_live/core/constants/app_constants.dart';
import 'package:imo_live/core/widgets/brand_assets.dart';
import 'package:imo_live/core/widgets/common_widgets.dart';

/// Guards the branding replacement.
///
/// The build proves the launcher icon compiles into `resources.arsc`; it says
/// nothing about whether the *Flutter* logo asset is packaged, and a missing
/// asset is invisible at runtime because [BrandMark] deliberately degrades to a
/// placeholder instead of throwing. These tests are what turn that silent
/// degradation into a failure.
///
/// `AppTheme.dark()`'s splash factory is overridden to `InkSplash` for the same
/// reason as `widget_smoke_test.dart`: `InkSparkle` lazily loads a shader that
/// is not in the test asset manifest.
Future<void> pumpThemed(
  WidgetTester tester,
  Widget child, {
  Size size = const Size(420, 900),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.dark().copyWith(splashFactory: InkSplash.splashFactory),
      home: Scaffold(body: child),
    ),
  );
}

/// The placeholder [BrandMark] and [BrandIcon] draw when an asset fails to load.
const IconData _missingAssetIcon = Icons.image_not_supported_outlined;

void main() {
  group('logo assets', () {
    testWidgets('both logo files are packaged and decode as images',
        (WidgetTester tester) async {
      // Byte presence alone is not enough — a truncated or mis-copied file still
      // has bytes. Decoding proves the file is a real image of the right size.
      await tester.runAsync(() async {
        for (final String path in <String>[
          BrandAssets.logo,
          BrandAssets.logoPlate,
        ]) {
          final ByteData data = await rootBundle.load(path);
          expect(data.lengthInBytes, greaterThan(1000),
              reason: '$path is missing or empty');

          final ui.Codec codec =
              await ui.instantiateImageCodec(data.buffer.asUint8List());
          final ui.FrameInfo frame = await codec.getNextFrame();
          expect(frame.image.width, greaterThanOrEqualTo(256),
              reason: '$path decoded smaller than any in-app placement needs');
          expect(frame.image.width, frame.image.height,
              reason: '$path must be square so both variants frame the mark alike');
          frame.image.dispose();
          codec.dispose();
        }
      });
    });

    test('the logo constants point at the raster assets, not the retired SVG',
        () {
      expect(BrandAssets.logo, 'assets/images/app_logo_transparent.png');
      expect(BrandAssets.logoPlate, 'assets/images/app_logo.jpg');
      // The mark is a gradient illustration; a .svg path here would mean
      // someone reverted to the old single-colour vector.
      expect(BrandAssets.logo.endsWith('.svg'), isFalse);
      expect(BrandAssets.logoPlate.endsWith('.svg'), isFalse);
    });
  });

  group('BrandMark', () {
    testWidgets('draws the transparent logo at the requested size, untinted',
        (WidgetTester tester) async {
      await pumpThemed(tester, const Center(child: BrandMark(size: 96)));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      final Image image = tester.widget<Image>(find.byType(Image));
      expect(image.width, 96);
      expect(image.height, 96);
      // Tinting with BlendMode.srcIn is what BrandIcon does; on a gradient mark
      // it would flatten the whole thing to a silhouette.
      expect(image.color, isNull);
      expect(image.image, isA<AssetImage>());
      expect((image.image as AssetImage).assetName, BrandAssets.logo);
      expect(find.byIcon(_missingAssetIcon), findsNothing,
          reason: 'the logo asset failed to load and fell back to the placeholder');
    });

    testWidgets('renders the opaque plate variant on request',
        (WidgetTester tester) async {
      await pumpThemed(
        tester,
        const Center(child: BrandMark(asset: BrandAssets.logoPlate, size: 72)),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      final Image image = tester.widget<Image>(find.byType(Image));
      expect((image.image as AssetImage).assetName, BrandAssets.logoPlate);
      expect(find.byIcon(_missingAssetIcon), findsNothing);
    });
  });

  group('BrandLockup', () {
    testWidgets('paints the mark and the wordmark without exceptions',
        (WidgetTester tester) async {
      // The glow is a boxShadow on a BoxShape.circle decoration with no fill.
      // That is a paint path worth exercising: if it asserted, the splash and
      // both auth screens would be the first thing a new user saw break.
      await pumpThemed(tester, const Center(child: BrandLockup()));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.byType(BrandMark), findsOneWidget);
      expect(find.text(AppConstants.appName), findsOneWidget);
      expect(find.text(AppConstants.appTagline), findsOneWidget);
    });

    testWidgets('hides the wordmark when asked', (WidgetTester tester) async {
      await pumpThemed(
        tester,
        const Center(child: BrandLockup(showName: false, showTagline: false)),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.byType(BrandMark), findsOneWidget);
      expect(find.text(AppConstants.appName), findsNothing);
    });
  });

  group('EmptyState', () {
    testWidgets('shows the logo instead of a themed glyph when given an imageAsset',
        (WidgetTester tester) async {
      await pumpThemed(
        tester,
        const EmptyState(
          imageAsset: BrandAssets.logo,
          title: 'No chats yet',
          message: 'Start a conversation and it will show up here.',
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.byType(BrandMark), findsOneWidget);
      expect(find.byIcon(_missingAssetIcon), findsNothing);
      // The tinted disc is deliberately dropped in this mode — a circular mark
      // inside a second circle reads as a misplaced ring.
      expect(find.byIcon(Icons.chat_bubble_outline_rounded), findsNothing);
    });

    testWidgets('still renders the icon disc when no imageAsset is given',
        (WidgetTester tester) async {
      await pumpThemed(
        tester,
        const EmptyState(
          icon: Icons.chat_bubble_outline_rounded,
          title: 'No chats yet',
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.byType(BrandMark), findsNothing);
      expect(find.byIcon(Icons.chat_bubble_outline_rounded), findsOneWidget);
    });
  });
}
