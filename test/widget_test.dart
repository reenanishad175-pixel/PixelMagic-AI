import 'package:flutter_test/flutter_test.dart';
import 'package:pixelmagic_ai/main.dart';

void main() {
  testWidgets('PixelMagic AI setup screen renders', (tester) async {
    await tester.pumpWidget(const PixelMagicApp());
    expect(find.text('PixelMagic AI'), findsOneWidget);
    expect(
      find.text('App setup is being completed. Please install the latest test build.'),
      findsOneWidget,
    );
  });
}
