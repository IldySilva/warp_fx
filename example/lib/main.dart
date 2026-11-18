import 'package:material_ui/material_ui.dart';

import 'pages/beams_page.dart';
import 'pages/center_page.dart';
import 'pages/horizontal_page.dart';
import 'pages/send_page.dart';

void main() => runApp(const ShowcaseApp());

class ShowcaseApp extends StatelessWidget {
  const ShowcaseApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'warp_fx',
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.dark,
      darkTheme: ThemeData(
        brightness: Brightness.dark,
        colorSchemeSeed: const Color(0xFF7C5CFF),
        scaffoldBackgroundColor: const Color(0xFF0B0B0F),
      ),
      home: const Showcase(),
    );
  }
}

class Showcase extends StatefulWidget {
  const Showcase({super.key});

  @override
  State<Showcase> createState() => _ShowcaseState();
}

class _ShowcaseState extends State<Showcase> {
  int _index = 0;

  static const _pages = <Widget>[
    SendPage(),
    HorizontalPage(),
    CenterPage(),
    BeamsPage(),
  ];

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 760;
    final destinations = const [
      (Icons.arrow_upward_rounded, 'Vertical'),
      (Icons.arrow_forward_rounded, 'Horizontal'),
      (Icons.radio_button_checked_rounded, 'Center'),
      (Icons.auto_awesome_rounded, 'Beams'),
    ];

    // On desktop and tablets the demo sits in a phone-sized frame beside a
    // rail; on phones it fills the screen.
    final page = IndexedStack(index: _index, children: _pages);

    if (!wide) {
      return Scaffold(
        body: page,
        bottomNavigationBar: NavigationBar(
          selectedIndex: _index,
          onDestinationSelected: (i) => setState(() => _index = i),
          destinations: [
            for (final (icon, label) in destinations)
              NavigationDestination(icon: Icon(icon), label: label),
          ],
        ),
      );
    }

    return Scaffold(
      body: Row(
        children: [
          NavigationRail(
            selectedIndex: _index,
            onDestinationSelected: (i) => setState(() => _index = i),
            labelType: NavigationRailLabelType.all,
            leading: const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Text(
                'warp_fx',
                textAlign: TextAlign.center,
                style: TextStyle(fontWeight: FontWeight.w700, height: 1.1),
              ),
            ),
            destinations: [
              for (final (icon, label) in destinations)
                NavigationRailDestination(icon: Icon(icon), label: Text(label)),
            ],
          ),
          const VerticalDivider(width: 1),
          Expanded(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                // A phone at its real size, scaled to fit the window.
                child: FittedBox(
                  child: SizedBox(
                    width: 390,
                    height: 844,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(48),
                      child: MediaQuery(
                        data: MediaQuery.of(context).copyWith(
                          size: const Size(390, 844),
                          padding: EdgeInsets.zero,
                          viewPadding: EdgeInsets.zero,
                        ),
                        child: page,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
