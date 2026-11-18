import 'package:warp_fx/warp_fx.dart';
import 'package:material_ui/material_ui.dart';

import '../widgets.dart';

/// The center wave: a success, as a ring from an avatar, inside a sheet.
/// The avatar is held sharp at the centre and morphs into a check.
class CenterPage extends StatefulWidget {
  const CenterPage({super.key});

  @override
  State<CenterPage> createState() => _CenterPageState();
}

class _CenterPageState extends State<CenterPage> {
  final _avatar = GlobalKey();
  bool _done = false;

  @override
  Widget build(BuildContext context) {
    return ScreenBackground(
      colors: const [Color(0xFF0B0B0F), Color(0xFF0B0B0F)],
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: SizedBox(
            height: 500,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(48),
              child: DistortionWave(
                isRevealed: _done,
                sourceKey: _avatar,
                style: DistortionWaveStyle.center,
                revealed: _Sheet(
                  avatarKey: null,
                  done: true,
                  onTap: () => setState(() => _done = false),
                ),
                child: _Sheet(
                  avatarKey: _avatar,
                  done: false,
                  onTap: () => setState(() => _done = true),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Sheet extends StatelessWidget {
  const _Sheet({
    required this.avatarKey,
    required this.done,
    required this.onTap,
  });

  final GlobalKey? avatarKey;
  final bool done;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF17171C),
      padding: const EdgeInsets.all(28),
      child: Column(
        children: [
          const Spacer(),
          Container(
            key: avatarKey,
            width: 96,
            height: 96,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: done ? const Color(0xFF35BA00) : const Color(0xFF2775CA),
            ),
            child: Icon(
              done ? Icons.check_rounded : Icons.attach_money_rounded,
              color: Colors.white,
              size: 52,
            ),
          ),
          const SizedBox(height: 28),
          Text(
            done ? 'Received 500 USDC' : 'Receive 500 USDC',
            style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          Text(
            done ? 'Added to your balance' : 'From the agent wallet · Base',
            style: const TextStyle(color: Colors.white60),
          ),
          const Spacer(),
          GestureDetector(
            onTap: onTap,
            child: PillButton(label: done ? 'Done — run it again' : 'Accept'),
          ),
        ],
      ),
    );
  }
}
