import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:video_player/video_player.dart';

import '../../local/storage/file_storage_service.dart';
import '../constants/app_constants.dart';

/// Renders the first usable frame of a video to a PNG on disk, for use as a
/// chat-bubble poster.
///
/// ### Why this exists
///
/// `Attachment.thumbnailPath` was read by the video bubble and written by
/// nothing, so every video in every chat rendered the same grey placeholder.
/// The field, the model plumbing and the bubble branch were all present — only
/// the producer was missing, which is exactly the kind of gap that looks
/// finished in a screenshot review.
///
/// ### How it works
///
/// A real `VideoPlayer` is mounted inside an invisible `RepaintBoundary` in the
/// app's overlay, seeked to [sampleAt], then captured with
/// `RenderRepaintBoundary.toImage()`. This is the only frame-capture route that
/// works from pure Dart with packages already in the build — `video_player`
/// exposes a texture id, and a texture cannot be read back as a `ui.Image`
/// directly.
///
/// ### Why not a plugin
///
/// `video_thumbnail` and similar add a native module, which changes the APK's
/// native library set. This costs zero new dependencies and cannot affect the
/// release build's native payload.
///
/// ### Failure is normal and must stay silent
///
/// A codec that will not open, a 0-byte file, no write permission: all return
/// `null` and the bubble falls back to its placeholder. A thumbnail is
/// decoration; it must never surface an error or block a send.
class VideoThumbnailer {
  const VideoThumbnailer({required this.storage});

  /// Where the generated poster is written. Public because it is a plain
  /// constructor dependency, not internal state.
  final FileStorageService storage;

  /// Width of the generated poster. Bubble posters are ~250dp wide, so 512px
  /// covers a 2× device with room to spare while keeping the file small.
  static const double targetWidth = 512;

  /// How far into the clip to sample. Frame 0 of a phone video is very often a
  /// black fade-in, which makes a useless thumbnail.
  static const Duration sampleAt = Duration(milliseconds: 600);

  /// How long to wait for the seeked frame to reach the texture before giving
  /// up. Generous: a cold decoder on a mid-range phone can take most of this.
  static const Duration _decodeBudget = Duration(milliseconds: 1400);

  /// Extracts a poster for [videoPath]; returns the stored absolute path, or
  /// `null` when a frame could not be produced.
  ///
  /// [context] must be a live element — the capture needs a render tree to
  /// paint into.
  Future<String?> generate(BuildContext context, String videoPath) async {
    // Resolve the overlay *before* any await. The overlay outlives the calling
    // widget's build, so holding it is safe, and it keeps this method free of a
    // `BuildContext` across an async gap — which is a real bug class (the widget
    // can be unmounted by the time the frame is ready).
    final OverlayState? overlay = Overlay.maybeOf(context, rootOverlay: true);
    if (overlay == null) return null;

    VideoPlayerController? controller;
    OverlayEntry? entry;
    try {
      final File source = File(videoPath);
      if (!await source.exists() || await source.length() < 1024) return null;

      controller = VideoPlayerController.file(source);
      await controller.initialize();
      await controller.setVolume(0);

      final Size size = controller.value.size;
      if (size.width <= 0 || size.height <= 0) return null;

      // Sample a little way in, so a fade-in does not become the poster.
      final Duration duration = controller.value.duration;
      if (duration > sampleAt) {
        await controller.seekTo(sampleAt);
      }

      final GlobalKey boundaryKey = GlobalKey();
      final double height = targetWidth * (size.height / size.width);

      entry = OverlayEntry(
        builder: (BuildContext _) => Positioned(
          // Off-screen but still laid out and painted: `Opacity(0)` or a
          // zero-size box would skip the paint that `toImage` needs.
          left: -targetWidth - 1,
          top: 0,
          child: IgnorePointer(
            child: RepaintBoundary(
              key: boundaryKey,
              child: SizedBox(
                width: targetWidth,
                height: height,
                child: VideoPlayer(controller!),
              ),
            ),
          ),
        ),
      );

      final OverlayState overlayState = overlay;
      overlayState.insert(entry);

      // Let the texture composite before capturing. Polling beats a fixed sleep:
      // a warm decoder is ready almost immediately.
      final ui.Image? image = await _captureWhenPainted(
        boundaryKey,
        targetWidth,
        height,
      );
      if (image == null) return null;

      final ByteData? bytes = await image.toByteData(
        format: ui.ImageByteFormat.png,
      );
      image.dispose();
      if (bytes == null) return null;

      return await storage.writeBytes(
        bytes.buffer.asUint8List(),
        AppConstants.dirThumbnails,
        extension: 'png',
      );
    } on Object {
      // Covers `Exception` (codec, IO) and `Error` (a missing platform channel
      // throws an `Error`, not an `Exception`). A poster is not worth failing a
      // send over, so both collapse to "no thumbnail".
      return null;
    } finally {
      entry?.remove();
      await controller?.dispose();
    }
  }

  /// Waits for [key]'s render object to exist and paint, then captures it.
  Future<ui.Image?> _captureWhenPainted(
    GlobalKey key,
    double width,
    double height,
  ) async {
    final Stopwatch clock = Stopwatch()..start();
    while (clock.elapsed < _decodeBudget) {
      final RenderObject? object = key.currentContext?.findRenderObject();
      if (object is RenderRepaintBoundary) {
        // `debugNeedsPaint` guards against capturing a blank layer: reading the
        // image while the boundary still needs painting yields transparent
        // pixels rather than the frame.
        if (!object.debugNeedsPaint) {
          return object.toImage(pixelRatio: 1);
        }
      }
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    final RenderObject? object = key.currentContext?.findRenderObject();
    if (object is RenderRepaintBoundary && !object.debugNeedsPaint) {
      return object.toImage(pixelRatio: 1);
    }
    return null;
  }
}
