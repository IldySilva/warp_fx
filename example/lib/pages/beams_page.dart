import 'package:warp_fx/warp_fx.dart';
import 'package:material_ui/material_ui.dart';

/// Border beams: every size, with live colour, theme and play controls.
class BeamsPage extends StatefulWidget {
  const BeamsPage({super.key});

  @override
  State<BeamsPage> createState() => _BeamsPageState();
}

class _BeamsPageState extends State<BeamsPage> {
  BorderBeamColorVariant _variant = BorderBeamColorVariant.colorful;
  bool _light = false;
  bool _active = true;

  @override
  Widget build(BuildContext context) {
    final theme = _light ? BorderBeamTheme.light : BorderBeamTheme.dark;
    final bg = _light ? const Color(0xFFF4F4F6) : const Color(0xFF0B0B0F);
    final card = _light ? Colors.white : const Color(0xFF1D1D1D);
    final fg = _light ? Colors.black87 : Colors.white;

    Widget box(String label, {double height = 120, double radius = 16}) =>
        Container(
          height: height,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: card,
            borderRadius: BorderRadius.circular(radius),
            border: Border.all(color: fg.withValues(alpha: 0.08)),
          ),
          child: Text(
            label,
            style: TextStyle(color: fg.withValues(alpha: 0.7)),
          ),
        );

    Widget beam(BorderBeamSize size, Widget child, {double? radius}) =>
        BorderBeam(
          size: size,
          colorVariant: _variant,
          theme: theme,
          active: _active,
          borderRadius: radius,
          child: child,
        );

    return ColoredBox(
      color: bg,
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Text(
              'Border beams',
              style: TextStyle(
                color: fg,
                fontSize: 28,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final v in BorderBeamColorVariant.values)
                  ChoiceChip(
                    label: Text(v.name),
                    selected: v == _variant,
                    onSelected: (_) => setState(() => _variant = v),
                  ),
                FilterChip(
                  label: const Text('light'),
                  selected: _light,
                  onSelected: (v) => setState(() => _light = v),
                ),
                FilterChip(
                  label: const Text('active'),
                  selected: _active,
                  onSelected: (v) => setState(() => _active = v),
                ),
              ],
            ),
            const SizedBox(height: 32),
            Row(
              children: [
                beam(
                  BorderBeamSize.sm,
                  box('sm', height: 36, radius: 18),
                  radius: 18,
                ),
                const SizedBox(width: 16),
                Expanded(child: beam(BorderBeamSize.md, box('md'))),
              ],
            ),
            const SizedBox(height: 32),
            beam(
              BorderBeamSize.line,
              box('line — ask the agent anything…', height: 56, radius: 16),
            ),
            const SizedBox(height: 32),
            beam(BorderBeamSize.pulseInner, box('pulseInner', height: 140)),
            const SizedBox(height: 48),
            beam(BorderBeamSize.pulseOutside, box('pulseOutside', height: 140)),
            const SizedBox(height: 48),
          ],
        ),
      ),
    );
  }
}
