import 'package:material_ui/material_ui.dart';

/// [global] in the coordinates of the widget with [key].
Offset? toLocal(GlobalKey key, Offset global) {
  final box = key.currentContext?.findRenderObject() as RenderBox?;
  return box?.globalToLocal(global);
}

/// An opaque screen background: the wave needs one to picture.
class ScreenBackground extends StatelessWidget {
  const ScreenBackground({
    super.key,
    required this.colors,
    required this.child,
  });

  final List<Color> colors;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: colors,
        ),
      ),
      child: DefaultTextStyle.merge(
        style: const TextStyle(color: Colors.white),
        child: SizedBox.expand(child: child),
      ),
    );
  }
}

class InfoRow extends StatelessWidget {
  const InfoRow({super.key, required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
        ),
      ),
      child: Row(
        children: [
          Text(label, style: const TextStyle(color: Colors.white54)),
          const Spacer(),
          const SizedBox(width: 16),
          Flexible(
            child: Text(
              value,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

/// A big white pill, the kind of button a wave opens from.
class PillButton extends StatelessWidget {
  const PillButton({super.key, required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 56,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(28),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Colors.black,
          fontSize: 17,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
