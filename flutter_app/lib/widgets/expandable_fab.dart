import 'package:flutter/material.dart';

import '../core/tokens.dart';

/// Açılır menüdeki tek işlem.
class FabAction {
  const FabAction({
    required this.label,
    required this.icon,
    required this.onPressed,
  });

  final String label;
  final IconData icon;
  final VoidCallback onPressed;
}

/// Sağ altta tek yüzen düğme: dokununca üstünde işlemler açılır, tekrar
/// dokununca (ya da bir işlem seçilince) kapanır. Birden fazla yüzen düğmenin
/// listeyi kapatmasını önler.
class ExpandableFab extends StatefulWidget {
  const ExpandableFab({
    super.key,
    required this.actions,
    this.icon = Icons.add,
    this.tooltip = 'İşlemler',
  });

  final List<FabAction> actions;
  final IconData icon;
  final String tooltip;

  @override
  State<ExpandableFab> createState() => _ExpandableFabState();
}

class _ExpandableFabState extends State<ExpandableFab>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 180),
  );
  bool _open = false;

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  void _toggle() {
    setState(() => _open = !_open);
    _open ? _c.forward() : _c.reverse();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final anim = CurvedAnimation(parent: _c, curve: Curves.easeOut);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        // Kapaliyken islemler agaca hic girmez: gorunmez dugmeler dokunmayi
        // yutmasin.
        if (_open || _c.isAnimating)
          FadeTransition(
            opacity: anim,
            // Kirpmayan gecis: dugme kenarliklari ve golgeleri kesilmesin.
            child: ScaleTransition(
              scale: anim,
              alignment: Alignment.bottomRight,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  for (final a in widget.actions) ...[
                    FloatingActionButton.extended(
                      heroTag: null,
                      backgroundColor: t.card,
                      foregroundColor: t.primary,
                      onPressed: () {
                        _toggle();
                        a.onPressed();
                      },
                      icon: Icon(a.icon),
                      label: Text(a.label),
                    ),
                    const SizedBox(height: 12),
                  ],
                ],
              ),
            ),
          ),
        FloatingActionButton(
          heroTag: null,
          tooltip: _open ? 'Kapat' : widget.tooltip,
          onPressed: _toggle,
          child: RotationTransition(
            turns: Tween<double>(begin: 0, end: 0.125).animate(anim),
            child: Icon(widget.icon),
          ),
        ),
      ],
    );
  }
}
