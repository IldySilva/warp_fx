import 'package:warp_fx_example/main.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('showcase builds', (tester) async {
    await tester.pumpWidget(const ShowcaseApp());
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('Confirm and send'), findsOneWidget);
  });
}
