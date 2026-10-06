import 'package:flutter/material.dart';

enum NoticeKind { info, success, error }

/// Every passing message in the app, in one look: a small floating card with
/// an icon, that goes away by itself.
///
/// Plain snack bars were a full-width strip along the bottom edge, bright
/// green or red when something was saved or failed, and those carrying a
/// button never left at all — Flutter keeps a snack bar with an action until
/// it is dismissed by hand. A new notice replaces the one on screen rather
/// than queueing behind it, so a burst of them does not play out for half a
/// minute.
void showNotice(
  BuildContext context,
  String message, {
  String? detail,
  NoticeKind kind = NoticeKind.info,
  String? actionLabel,
  VoidCallback? onAction,
  Duration? duration,
}) {
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (messenger == null) return;
  messenger
    ..clearSnackBars()
    ..showSnackBar(
      noticeBar(
        message,
        detail: detail,
        kind: kind,
        actionLabel: actionLabel,
        onAction: onAction,
        duration: duration,
      ),
    );
}

/// The snack bar [showNotice] shows, for code that holds a messenger rather
/// than a context.
SnackBar noticeBar(
  String message, {
  String? detail,
  NoticeKind kind = NoticeKind.info,
  String? actionLabel,
  VoidCallback? onAction,
  Duration? duration,
}) => SnackBar(
  // Never kept on screen: an action is an offer, not a reason to stay.
  persist: false,
  duration:
      duration ??
      (kind == NoticeKind.error
          ? const Duration(seconds: 6)
          : const Duration(seconds: 4)),
  content: _NoticeBody(message: message, detail: detail, kind: kind),
  action: actionLabel == null
      ? null
      : SnackBarAction(label: actionLabel, onPressed: onAction ?? () {}),
);

class _NoticeBody extends StatelessWidget {
  final String message;
  final String? detail;
  final NoticeKind kind;
  const _NoticeBody({required this.message, this.detail, required this.kind});

  @override
  Widget build(BuildContext context) {
    final (icon, accent) = switch (kind) {
      NoticeKind.success => (
        Icons.check_circle_rounded,
        const Color(0xFF34D399),
      ),
      NoticeKind.error => (Icons.error_rounded, const Color(0xFFF87171)),
      NoticeKind.info => (Icons.info_rounded, const Color(0xFF93C5E8)),
    };
    final text =
        Theme.of(context).snackBarTheme.contentTextStyle?.color ?? Colors.white;
    return Row(
      children: [
        Container(
          width: 30,
          height: 30,
          decoration: BoxDecoration(
            color: accent.withValues(alpha: .16),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, size: 18, color: accent),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                message,
                style: TextStyle(
                  fontSize: 13.5,
                  height: 1.3,
                  fontWeight: detail == null
                      ? FontWeight.w500
                      : FontWeight.w600,
                  color: text,
                ),
              ),
              if (detail != null)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    detail!,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      height: 1.3,
                      color: text.withValues(alpha: .7),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
