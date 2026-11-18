import 'package:warp_fx/warp_fx.dart';
import 'package:material_ui/material_ui.dart';

import '../widgets.dart';

/// The vertical wave: confirming a payment, from the button at the bottom.
class SendPage extends StatefulWidget {
  const SendPage({super.key});

  @override
  State<SendPage> createState() => _SendPageState();
}

class _SendPageState extends State<SendPage> {
  final _wave = GlobalKey();
  final _button = GlobalKey();
  bool _sent = false;
  Offset? _focus;

  void _send(TapDownDetails details) {
    setState(() {
      _focus = toLocal(_wave, details.globalPosition);
      _sent = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(
          child: DistortionWave(
            key: _wave,
            isRevealed: _sent,
            sourceKey: _button,
            focus: _focus,
            revealed: const _Receipt(),
            child: const _Review(),
          ),
        ),
        // Above the wave, so it stays sharp and live while the wave passes.
        Positioned(
          left: 24,
          right: 24,
          bottom: 30,
          child: _sent
              ? Center(
                  child: TextButton.icon(
                    onPressed: () => setState(() => _sent = false),
                    icon: const Icon(Icons.undo_rounded),
                    label: const Text('Collapse back'),
                  ),
                )
              : GestureDetector(
                  onTapDown: _send,
                  child: PillButton(key: _button, label: 'Confirm and send'),
                ),
        ),
      ],
    );
  }
}

class _Review extends StatelessWidget {
  const _Review();

  @override
  Widget build(BuildContext context) {
    return ScreenBackground(
      colors: const [Color(0xFF16161D), Color(0xFF0B0B0F)],
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 120),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Review transfer',
                style: TextStyle(fontSize: 15, color: Colors.white54),
              ),
              const SizedBox(height: 28),
              const Center(
                child: Text(
                  '\$1,250.00',
                  style: TextStyle(
                    fontSize: 56,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -2,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              const Center(
                child: Text(
                  'to Ana Martins',
                  style: TextStyle(color: Colors.white60),
                ),
              ),
              const SizedBox(height: 40),
              const InfoRow(label: 'From', value: 'Everyday •• 4021'),
              const InfoRow(label: 'Arrives', value: 'In seconds'),
              const InfoRow(label: 'Fee', value: 'Free'),
              const InfoRow(label: 'Note', value: 'Dinner 🍜'),
              const Spacer(),
              Text(
                'Tap the button anywhere along its length: the wave leans toward your finger.',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.4),
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Receipt extends StatelessWidget {
  const _Receipt();

  @override
  Widget build(BuildContext context) {
    return ScreenBackground(
      colors: const [Color(0xFF101A2E), Color(0xFF0B0B0F)],
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 64, 24, 120),
          child: Column(
            children: [
              Container(
                width: 84,
                height: 84,
                decoration: const BoxDecoration(
                  color: Color(0xFF35BA00),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.check_rounded,
                  size: 48,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 28),
              const Text(
                'Sent',
                style: TextStyle(fontSize: 34, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              const Text(
                '\$1,250.00 is on its way to Ana',
                style: TextStyle(color: Colors.white60),
              ),
              const SizedBox(height: 40),
              const InfoRow(label: 'Reference', value: 'TX-48A1-90F2'),
              const InfoRow(label: 'Status', value: 'Completed'),
            ],
          ),
        ),
      ),
    );
  }
}
