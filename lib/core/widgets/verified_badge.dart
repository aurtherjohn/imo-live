import 'package:flutter/material.dart';

import '../../app/theme/app_color_scheme.dart';

/// The verified tick shown next to a confirmed Imo LIVE account.
///
/// Shared by the directory search results, the contact lookup panel and the
/// profile screens so the badge looks identical everywhere the directory
/// surfaces a `users/{uid}.isVerified == true`.
class VerifiedBadge extends StatelessWidget {
  const VerifiedBadge({super.key, this.size = 15});

  final double size;

  @override
  Widget build(BuildContext context) => Icon(
        Icons.verified_rounded,
        size: size,
        color: context.c.onInfo,
      );
}
