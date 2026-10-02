import 'package:flutter/material.dart';

import '../core/tokens.dart';

/// Kaydırınca açılan tek işlem (Düzenle, Sil...).
class SwipeAction {
  const SwipeAction({
    required this.label,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
}

/// Satır soldan sağa kaydırıldığında altındaki işlemleri (düzenle, sil)
/// açar. Bırakınca yarıdan fazla açıksa açık kalır, değilse kapanır; açıkken
/// satıra dokunmak ya da bir işlemi seçmek satırı kapatır.
///
/// Aynı anda yalnızca bir satır açık durur: yeni bir satır açılınca önceki
/// kendiliğinden kapanır.
class SwipeActions extends StatefulWidget {
  const SwipeActions({
    super.key,
    required this.child,
    required this.actions,
    this.actionWidth = 76,
    this.radius = AppRadius.md,
  });

  final Widget child;
  final List<SwipeAction> actions;
  final double actionWidth;
  final double radius;

  @override
  State<SwipeActions> createState() => _SwipeActionsState();
}

/// Açık olan satır; yenisi açılınca kapatılır.
_SwipeActionsState? _acik;

class _SwipeActionsState extends State<SwipeActions>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 180),
  );

  double get _max => widget.actionWidth * widget.actions.length;

  @override
  void dispose() {
    if (identical(_acik, this)) _acik = null;
    _c.dispose();
    super.dispose();
  }

  void _open() {
    if (_acik != null && !identical(_acik, this)) _acik!._close();
    _acik = this;
    _c.animateTo(1, curve: Curves.easeOut);
  }

  void _close() {
    if (identical(_acik, this)) _acik = null;
    _c.animateTo(0, curve: Curves.easeOut);
  }

  void _onUpdate(DragUpdateDetails d) {
    _c.value = (_c.value + d.primaryDelta! / _max).clamp(0.0, 1.0);
  }

  void _onEnd(DragEndDetails d) {
    final v = d.primaryVelocity ?? 0;
    if (v > 300 || (v > -300 && _c.value > 0.5)) {
      _open();
    } else {
      _close();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.actions.isEmpty) return widget.child;
    // Kapaliyken kirpma ve zemin uygulanmaz: kartin kenar cizgisi ve
    // golgesi oldugu gibi kalir. Agac yapisi degismez ki suruklerken
    // hareket kesilmesin.
    return AnimatedBuilder(
      animation: _c,
      builder: (context, child) => ClipRRect(
        borderRadius: BorderRadius.circular(widget.radius),
        clipBehavior: _c.value == 0 ? Clip.none : Clip.antiAlias,
        child: child,
      ),
      child: Stack(
        children: [
          // Islem katmani yalnizca satir kaydirilinca cizilir; kapaliyken
          // kartin saydam kenarlarindan gorunmesin.
          Positioned.fill(
            child: AnimatedBuilder(
              animation: _c,
              builder: (context, child) =>
                  _c.value == 0 ? const SizedBox.shrink() : child!,
              child: Row(
                children: [
                  for (final a in widget.actions)
                    SizedBox(
                      width: widget.actionWidth,
                      child: Material(
                        color: a.color,
                        child: InkWell(
                          onTap: () {
                            _close();
                            a.onTap();
                          },
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(a.icon, color: Colors.white, size: 22),
                              const SizedBox(height: 4),
                              Text(
                                a.label,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: AppFontSize.label,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          AnimatedBuilder(
            animation: _c,
            builder: (context, child) => Transform.translate(
              offset: Offset(_c.value * _max, 0),
              child: child,
            ),
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onHorizontalDragUpdate: _onUpdate,
              onHorizontalDragEnd: _onEnd,
              onTap: () {
                if (_c.value > 0) _close();
              },
              // Opak zemin: kaydirilan kart altindaki islemleri ortmeli.
              child: AnimatedBuilder(
                animation: _c,
                builder: (context, child) => ColoredBox(
                  color: _c.value == 0
                      ? Colors.transparent
                      : context.tokens.card,
                  child: child,
                ),
                child: widget.child,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
