import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../app/theme/app_color_scheme.dart';
import '../../../../core/models/channel_models.dart';
import '../../../../core/widgets/common_widgets.dart';
import '../../../../core/utils/l10n.dart';

/// Opens a channel post's media.
///
/// ### Why this is a free function in its own file
///
/// Both the management feed (`ChannelScreen`) and the conversation view
/// (`ChannelChatScreen`) need to open the same post, and they must behave
/// identically — a video that plays from one and downloads a file from the
/// other is exactly the kind of drift that makes an app feel unfinished. One
/// implementation, two callers.
///
/// Images get the in-app pinch-zoom viewer. Video and files are handed to
/// whichever installed app can handle them: bundling a player to satisfy a
/// feature that only has to *work* would add native code to every APK, and the
/// system player already covers every format an uploader might send.
Future<void> openChannelPostMedia(
  BuildContext context,
  ChannelPost post,
) async {
  if (!post.hasMedia) return;

  if (post.isImage) {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (BuildContext context) => ChannelImageViewer(
          url: post.mediaUrl,
          caption: post.text,
        ),
        fullscreenDialog: true,
      ),
    );
    return;
  }

  final Uri? uri = Uri.tryParse(post.mediaUrl);
  if (uri == null) {
    if (context.mounted) {
      iToast(context, context.l10n.thisAttachmentHasNoUsable, isError: true);
    }
    return;
  }
  final bool opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
  if (!opened && context.mounted) {
    iToast(context, context.l10n.noAppOnThisDevice, isError: true);
  }
}

/// Full-screen pinch-zoom viewer for a channel image.
///
/// Deliberately not `PhotoView`-based like the chat viewer: a channel image has
/// no pager to swipe between, so the gallery machinery the chat viewer needs
/// would only be dead weight here.
class ChannelImageViewer extends StatelessWidget {
  const ChannelImageViewer({super.key, required this.url, this.caption = ''});

  final String url;
  final String caption;

  @override
  Widget build(BuildContext context) {
    final AppColorScheme c = context.c;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      extendBodyBehindAppBar: true,
      body: Column(
        children: <Widget>[
          Expanded(
            child: InteractiveViewer(
              minScale: 1,
              maxScale: 5,
              child: Center(
                child: Image.network(
                  url,
                  fit: BoxFit.contain,
                  errorBuilder: (
                    BuildContext context,
                    Object error,
                    StackTrace? stack,
                  ) =>
                      Icon(
                    Icons.broken_image_outlined,
                    color: c.textSecondary,
                    size: 48,
                  ),
                  loadingBuilder: (
                    BuildContext context,
                    Widget child,
                    ImageChunkEvent? progress,
                  ) {
                    if (progress == null) return child;
                    return const Center(child: ILoader());
                  },
                ),
              ),
            ),
          ),
          if (caption.trim().isNotEmpty)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                caption,
                style: const TextStyle(color: Colors.white, fontSize: 14),
              ),
            ),
        ],
      ),
    );
  }
}
