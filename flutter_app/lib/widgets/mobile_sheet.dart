import 'dart:ui';

import 'package:flutter/material.dart';

import '../core/tokens.dart';

Future<T?> showAppSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
}) {
  return showGeneralDialog<T>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Kapat',
    barrierColor: Colors.transparent,
    transitionDuration: const Duration(milliseconds: 180),
    pageBuilder: (ctx, _, _) => Stack(
      children: [
        Positioned.fill(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
            child: GestureDetector(
              onTap: () => Navigator.maybePop(ctx),
              child: ColoredBox(color: const Color(0x66111827)),
            ),
          ),
        ),
        SafeArea(
          bottom: false,
          child: Align(
            alignment: MediaQuery.sizeOf(ctx).width < 600
                ? Alignment.bottomCenter
                : Alignment.center,
            child: Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.viewInsetsOf(ctx).bottom,
              ),
              child: builder(ctx),
            ),
          ),
        ),
      ],
    ),
    transitionBuilder: (_, animation, _, child) =>
        FadeTransition(opacity: animation, child: child),
  );
}

class MobileSheet extends StatelessWidget {
  const MobileSheet({
    super.key,
    required this.title,
    required this.child,
    required this.footer,
    this.subtitle,
    this.icon,
    this.busy = false,
    this.background,
  });
  final Widget title, child, footer;
  final String? subtitle;
  final IconData? icon;
  final bool busy;
  final Color? background;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final media = MediaQuery.of(context);
    return PopScope(
      canPop: !busy,
      child: Material(
        color: background ?? t.card,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
        clipBehavior: Clip.antiAlias,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: 560,
            maxHeight:
                (media.size.height -
                    media.padding.top -
                    media.viewInsets.bottom) *
                .94,
          ),
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 48,
                  height: 5,
                  margin: const EdgeInsets.only(top: 12, bottom: 8),
                  decoration: BoxDecoration(
                    color: t.border,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(22, 0, 12, 8),
                  child: Row(
                    children: [
                      if (icon != null) ...[
                        Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: t.primarySoft,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Icon(icon, size: 21, color: t.primary),
                        ),
                        const SizedBox(width: 10),
                      ],
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            DefaultTextStyle(
                              style: Theme.of(context).textTheme.titleMedium!
                                  .copyWith(
                                    color: t.ink,
                                    fontSize: 17,
                                    fontWeight: FontWeight.w800,
                                  ),
                              child: title,
                            ),
                            if (subtitle != null)
                              Padding(
                                padding: const EdgeInsets.only(top: 3),
                                child: Text(
                                  subtitle!,
                                  style: TextStyle(
                                    color: t.muted,
                                    fontSize: 11,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: 'Kapat',
                        onPressed: busy ? null : () => Navigator.pop(context),
                        style: IconButton.styleFrom(backgroundColor: t.bg),
                        icon: const Icon(Icons.close, size: 20),
                      ),
                    ],
                  ),
                ),
                Flexible(
                  child: SingleChildScrollView(
                    keyboardDismissBehavior:
                        ScrollViewKeyboardDismissBehavior.onDrag,
                    padding: const EdgeInsets.fromLTRB(22, 4, 22, 16),
                    child: child,
                  ),
                ),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.fromLTRB(22, 14, 22, 16),
                  decoration: BoxDecoration(
                    color: t.card,
                    border: Border(
                      top: BorderSide(color: t.border.withValues(alpha: .5)),
                    ),
                  ),
                  child: footer,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
