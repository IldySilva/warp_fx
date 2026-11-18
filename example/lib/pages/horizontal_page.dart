import 'package:warp_fx/warp_fx.dart';
import 'package:material_ui/material_ui.dart';

import '../widgets.dart';

/// The horizontal wave: going on to the next step, from a tab on the left
/// edge. The same view on both sides — the wave carries the screen into
/// itself while its content changes underneath.
class HorizontalPage extends StatefulWidget {
  const HorizontalPage({super.key});

  @override
  State<HorizontalPage> createState() => _HorizontalPageState();
}

class _HorizontalPageState extends State<HorizontalPage> {
  final _wave = GlobalKey();
  final _tab = GlobalKey();
  bool _flip = false;
  int _step = 0;
  Offset? _focus;

  static const _steps = [
    (
      'Ask anything',
      'One prompt. Your whole workspace as context.',
      Color(0xFF1B1530),
    ),
    (
      'Watch it think',
      'Plans, tools and drafts stream in as they happen.',
      Color(0xFF10202A),
    ),
    ('Ship it', 'Review the diff, press the button, done.', Color(0xFF2A1515)),
  ];

  void _next(TapDownDetails details) {
    setState(() {
      _focus = toLocal(_wave, details.globalPosition);
      _flip = !_flip;
      _step = (_step + 1) % _steps.length;
    });
  }

  @override
  Widget build(BuildContext context) {
    final (title, body, tint) = _steps[_step];
    return Stack(
      children: [
        Positioned.fill(
          child: DistortionWave(
            key: _wave,
            isRevealed: _flip,
            sourceKey: _tab,
            focus: _focus,
            style: DistortionWaveStyle.horizontal.copyWith(
              palette: WavePalette.ocean,
            ),
            child: ScreenBackground(
              colors: [tint, const Color(0xFF0B0B0F)],
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(56, 80, 32, 32),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Step ${_step + 1} of ${_steps.length}',
                        style: const TextStyle(color: Colors.white54),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        title,
                        style: const TextStyle(
                          fontSize: 40,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -1,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        body,
                        style: const TextStyle(
                          fontSize: 18,
                          color: Colors.white70,
                        ),
                      ),
                      const Spacer(),
                      const Text(
                        'Tap the tab on the left edge →',
                        style: TextStyle(color: Colors.white38),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
        Positioned(
          left: 0,
          top: 0,
          bottom: 0,
          child: Center(
            child: GestureDetector(
              onTapDown: _next,
              child: Container(
                key: _tab,
                width: 22,
                height: 260,
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.horizontal(
                    right: Radius.circular(11),
                  ),
                ),
                child: const Icon(
                  Icons.chevron_right_rounded,
                  color: Colors.black,
                  size: 20,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
