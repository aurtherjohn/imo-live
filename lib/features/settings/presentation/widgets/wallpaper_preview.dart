import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../app/theme/app_color_scheme.dart';
import '../../../../app/theme/app_tokens.dart';
import '../../../../core/models/settings.dart';
import '../../../../core/utils/l10n.dart';

/// Renders the actual background of a [Wallpaper] — the same painter the chat
/// screen uses, so the picker preview is faithful.
class WallpaperBackground extends StatelessWidget {
  const WallpaperBackground({
    super.key,
    required this.wallpaper,
    this.child,
    this.dim = 0.0,
  });

  final Wallpaper wallpaper;
  final Widget? child;
  final double dim;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme c = context.c;
    final List<Color> colors = wallpaper.colors.isEmpty
        ? <Color>[c.bg]
        : wallpaper.colors.map(Color.new).toList();

    Widget background;

    switch (wallpaper.kind) {
      case WallpaperKind.image:
        final String? path = wallpaper.imagePath;
        if (path != null && path.isNotEmpty && File(path).existsSync()) {
          background = Image.file(
            File(path),
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) => ColoredBox(color: c.bg),
          );
        } else {
          background = ColoredBox(color: c.bg);
        }
      case WallpaperKind.solid:
        background = ColoredBox(color: colors.first);
      case WallpaperKind.gradient:
        background = DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: colors.length >= 2
                  ? colors
                  : <Color>[colors.first, colors.first],
            ),
          ),
        );
      case WallpaperKind.pattern:
        background = CustomPaint(
          painter: WallpaperPatternPainter(
            index: wallpaper.patternIndex,
            base: colors.first,
            line: colors.length >= 2 ? colors[1] : c.divider,
          ),
          child: const SizedBox.expand(),
        );
      case WallpaperKind.defaultPattern:
        background = CustomPaint(
          painter: WallpaperPatternPainter(
            index: 0,
            base: colors.first,
            line: colors.length >= 2 ? colors[1] : c.divider,
            faint: true,
          ),
          child: const SizedBox.expand(),
        );
    }

    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        background,
        if (dim > 0) ColoredBox(color: Colors.black.withValues(alpha: dim)),
        ?child,
      ],
    );
  }
}

/// A small square swatch used inside the wallpaper grid.
class WallpaperSwatch extends StatelessWidget {
  const WallpaperSwatch({super.key, required this.wallpaper});

  final Wallpaper wallpaper;

  @override
  Widget build(BuildContext context) => WallpaperBackground(wallpaper: wallpaper);
}

/// Draws the decorative patterns offered by the wallpaper presets.
class WallpaperPatternPainter extends CustomPainter {
  const WallpaperPatternPainter({
    required this.index,
    required this.base,
    required this.line,
    this.faint = false,
  });

  final int index;
  final Color base;
  final Color line;
  final bool faint;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = base);

    final double alpha = faint ? 0.10 : 0.22;
    final Paint paint = Paint()
      ..color = line.withValues(alpha: alpha)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4;

    switch (index) {
      case 0: // dots
        const double step = 22;
        final Paint dot = Paint()..color = line.withValues(alpha: alpha);
        for (double y = step / 2; y < size.height; y += step) {
          for (double x = step / 2; x < size.width; x += step) {
            canvas.drawCircle(Offset(x, y), 1.6, dot);
          }
        }
      case 1: // grid
        const double step = 28;
        for (double x = 0; x <= size.width; x += step) {
          canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
        }
        for (double y = 0; y <= size.height; y += step) {
          canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
        }
      case 2: // waves
        final Path path = Path();
        const double waveHeight = 26;
        final double amplitude = size.height / 12;
        for (double y = 0; y <= size.height + waveHeight; y += waveHeight) {
          path.moveTo(0, y);
          for (double x = 0; x <= size.width; x += 4) {
            path.lineTo(
              x,
              y + math.sin((x / size.width) * math.pi * 2) * amplitude * 0.5,
            );
          }
        }
        canvas.drawPath(path, paint);
      case 3: // bubbles
        final Paint bubble = Paint()
          ..color = line.withValues(alpha: alpha)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2;
        final math.Random random = math.Random(7);
        for (int i = 0; i < 26; i++) {
          canvas.drawCircle(
            Offset(
              random.nextDouble() * size.width,
              random.nextDouble() * size.height,
            ),
            random.nextDouble() * 22 + 6,
            bubble,
          );
        }
      case 4: // diagonal hatch
        const double step = 26;
        for (double x = -size.height; x < size.width; x += step) {
          canvas.drawLine(
            Offset(x, size.height),
            Offset(x + size.height, 0),
            paint,
          );
        }
      default: // crosshatch
        const double step = 34;
        for (double x = 0; x <= size.width; x += step) {
          canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
        }
        for (double y = 0; y <= size.height; y += step) {
          canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
        }
    }
  }

  @override
  bool shouldRepaint(WallpaperPatternPainter old) =>
      old.index != index ||
      old.base != base ||
      old.line != line ||
      old.faint != faint;
}

/// A miniature chat conversation used to preview a wallpaper choice.
class WallpaperChatPreview extends StatelessWidget {
  const WallpaperChatPreview({super.key, required this.wallpaper});

  final Wallpaper wallpaper;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: AppRadius.rLg,
      child: SizedBox(
        height: 260,
        child: WallpaperBackground(
          wallpaper: wallpaper,
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                _PreviewBubble(
                  text: context.l10n.heyHowDoesThisWallpaper,
                  outgoing: false,
                  time: '09:41',
                ),
                const SizedBox(height: AppSpacing.sm),
                _PreviewBubble(
                  text: context.l10n.looksGreatInDarkMode,
                  outgoing: true,
                  time: '09:42',
                ),
                const SizedBox(height: AppSpacing.sm),
                _PreviewBubble(
                  text: context.l10n.tryADifferentOneFrom,
                  outgoing: false,
                  time: '09:42',
                ),
                const Spacer(),
                const _PreviewComposer(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PreviewBubble extends StatelessWidget {
  const _PreviewBubble({
    required this.text,
    required this.outgoing,
    required this.time,
  });

  final String text;
  final bool outgoing;
  final String time;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme c = context.c;
    return Align(
      alignment: outgoing ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 230),
        child: Container(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.md,
            AppSpacing.sm,
            AppSpacing.md,
            AppSpacing.xs + 2,
          ),
          decoration: BoxDecoration(
            color: outgoing ? c.bubbleOut : c.bubbleIn,
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(AppRadius.lg),
              topRight: const Radius.circular(AppRadius.lg),
              bottomLeft: Radius.circular(outgoing ? AppRadius.lg : AppRadius.xs),
              bottomRight:
                  Radius.circular(outgoing ? AppRadius.xs : AppRadius.lg),
            ),
            border: Border.all(
              color: c.divider.withValues(alpha: 0.6),
              width: 0.6,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(
                text,
                style: context.t.bodyMedium?.copyWith(
                  color: c.textPrimary,
                  height: 1.3,
                ),
              ),
              const SizedBox(height: 2),
              Align(
                alignment: Alignment.centerRight,
                child: Text(
                  time,
                  style: context.t.labelSmall?.copyWith(
                    color: c.textSecondary,
                    fontSize: 10,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PreviewComposer extends StatelessWidget {
  const _PreviewComposer();

  @override
  Widget build(BuildContext context) {
    final AppColorScheme c = context.c;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: c.elevated.withValues(alpha: 0.92),
        borderRadius: AppRadius.rPill,
        border: Border.all(color: c.divider, width: 0.6),
      ),
      child: Row(
        children: <Widget>[
          Icon(Icons.emoji_emotions_outlined, size: AppIconSizes.sm, color: c.textSecondary),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              context.l10n.message,
              style: context.t.bodyMedium?.copyWith(color: c.textSecondary),
            ),
          ),
          Icon(Icons.attach_file_rounded, size: AppIconSizes.sm, color: c.textSecondary),
          const SizedBox(width: AppSpacing.sm),
          Icon(Icons.mic_none_rounded, size: AppIconSizes.sm, color: c.textSecondary),
        ],
      ),
    );
  }
}
