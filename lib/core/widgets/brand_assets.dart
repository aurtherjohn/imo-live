import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../app/theme/app_color_scheme.dart';
import '../../app/theme/app_tokens.dart';
import '../constants/app_constants.dart';
import '../utils/l10n.dart';

/// Every asset the app ships.
///
/// Centralised so a screen never hard-codes a path — a typo becomes a compile
/// error instead of a blank box at runtime, and renaming an asset is a
/// single-line change.
///
/// Two families live here:
///
/// * [BrandIcon] assets are **vectors** (`.svg`), rendered through
///   `flutter_svg`. They are line icons and third-party provider marks, which
///   are single-colour or few-colour flat shapes that stay crisp at any density.
/// * [BrandMark] assets are **rasters**, the app's own logo. That mark is a
///   gradient illustration rather than a flat glyph, so it cannot be
///   reconstructed by tinting a vector — it ships pre-rendered instead.
class BrandAssets {
  const BrandAssets._();

  static const String _dir = 'assets/brand';
  static const String _imagesDir = 'assets/images';

  /// The Imo LIVE mark, transparent. The working logo — used wherever it sits
  /// on the app's own surface (splash, auth lockup, top bar, empty states).
  static const String logo = '$_imagesDir/app_logo_transparent.png';

  /// The same mark on an opaque white plate. Used by the one surface that
  /// presents the brand as a card rather than compositing it onto the app's
  /// background — see `about_screen.dart`.
  ///
  /// Both files frame the mark identically (72.2% of the canvas, equal relative
  /// margins), so passing the same `size` to [BrandMark] renders the mark at
  /// the same scale from either one.
  static const String logoPlate = '$_imagesDir/app_logo.jpg';

  /// Multi-colour Google "G".
  static const String google = '$_dir/google_logo.svg';

  /// Auth field icons.
  static const String mail = '$_dir/icon_mail.svg';
  static const String lock = '$_dir/icon_lock.svg';
  static const String eye = '$_dir/icon_eye.svg';
  static const String eyeOff = '$_dir/icon_eye_off.svg';
  static const String userCheck = '$_dir/icon_user_check.svg';
}

/// Renders a vector asset, tinted to the current theme.
///
/// [color] is applied with `BlendMode.srcIn`, which recolours the whole glyph
/// from a single line icon to a multi-colour brand mark. Pass `null` to keep
/// the artwork's own colours (what the Google mark needs); the
/// monochrome icon set uses `currentColor` in the SVG, so tinting is what makes
/// it follow the accent colour.
class BrandIcon extends StatelessWidget {
  const BrandIcon(
    this.asset, {
    super.key,
    this.size = 22,
    this.color,
    this.semanticLabel,
  });

  final String asset;
  final double size;
  final Color? color;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final Widget svg = SvgPicture.asset(
      asset,
      width: size,
      height: size,
      fit: BoxFit.contain,
      colorFilter: color == null
          ? null
          : ColorFilter.mode(color!, BlendMode.srcIn),
      semanticsLabel: semanticLabel,
      // A missing asset must not take the screen down; the app degrades to a
      // neutral placeholder while the rest of the UI stays usable.
      placeholderBuilder: (BuildContext context) => SizedBox(
        width: size,
        height: size,
        child: Icon(
          Icons.image_not_supported_outlined,
          size: size * 0.8,
          color: context.c.textSecondary,
        ),
      ),
    );
    if (semanticLabel == null) return svg;
    return Semantics(label: semanticLabel, image: true, child: svg);
  }
}

/// Renders the app's own logo.
///
/// Unlike [BrandIcon] this never tints: the mark is a gradient illustration and
/// its own colours *are* the brand, so a `BlendMode.srcIn` filter would flatten
/// it to a silhouette. It is a raster for the same reason — a single-colour
/// vector cannot carry the gradient.
///
/// [size] is the edge of the drawn mark, not of some padded box: both files in
/// `assets/images/` are cropped tight to the artwork, so an N-pixel request
/// draws an N-pixel mark and callers can space it like any other square widget.
class BrandMark extends StatelessWidget {
  const BrandMark({
    super.key,
    this.asset = BrandAssets.logo,
    this.size = 48,
    this.semanticLabel,
  });

  final String asset;
  final double size;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      asset,
      width: size,
      height: size,
      fit: BoxFit.contain,
      // The transparent asset is 361 px and is drawn as small as 22 px. The
      // default filter is tuned for photos and lets the thin gradient ring
      // alias; the high-quality filter is what keeps it clean at tab-bar size.
      filterQuality: FilterQuality.high,
      semanticLabel: semanticLabel,
      // A missing asset must not take the screen down — same contract as
      // BrandIcon, so a packaging mistake degrades instead of crashing.
      errorBuilder: (BuildContext context, Object error, StackTrace? stack) =>
          SizedBox(
            width: size,
            height: size,
            child: Icon(
              Icons.image_not_supported_outlined,
              size: size * 0.8,
              color: context.c.textSecondary,
            ),
          ),
    );
  }
}

/// The Imo LIVE wordmark: the mark plus the app name, used on the splash and
/// both auth screens so the branding is identical everywhere.
class BrandLockup extends StatelessWidget {
  const BrandLockup({
    super.key,
    this.size = 84,
    this.showName = true,
    this.showTagline = true,
  });

  final double size;
  final bool showName;
  final bool showTagline;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        DecoratedBox(
          decoration: BoxDecoration(
            // The mark is a transparent ring, not an opaque tile, so the
            // rounded-rect drop shadow that used to sit here would have traced
            // a square that is no longer in the artwork. A blurred circle reads
            // as light coming off the ring instead of a box behind it.
            shape: BoxShape.circle,
            boxShadow: <BoxShadow>[
              BoxShadow(
                color: AppColors.accent.withValues(alpha: 0.30),
                blurRadius: size * 0.46,
                spreadRadius: size * 0.02,
              ),
            ],
          ),
          child: BrandMark(
            size: size,
            semanticLabel: AppConstants.appName,
          ),
        ),
        if (showName) ...<Widget>[
          SizedBox(height: size * 0.22),
          Text(
            context.l10n.appName,
            style: TextStyle(
              fontSize: 29,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.7,
              color: Colors.white,
            ),
          ),
        ],
        if (showTagline) ...<Widget>[
          const SizedBox(height: 6),
          Text(
            context.l10n.appTagline,
            style: TextStyle(
              fontSize: 13,
              letterSpacing: 0.3,
              fontWeight: FontWeight.w500,
              color: Colors.white.withValues(alpha: 0.55),
            ),
          ),
        ],
      ],
    );
  }
}
