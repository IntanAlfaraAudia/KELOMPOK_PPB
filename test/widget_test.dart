import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cuaca_tugaspbb/main.dart';

void main() {
  testWidgets('Aplikasi Cuaca Kampus tampil dengan judul dan tombol menu',
      (WidgetTester tester) async {
    await tester.pumpWidget(const CuacaKampusApp());
    await tester.pump();

    // Judul pada AppBar
    expect(find.text('Cuaca Kampus'), findsOneWidget);

    // Tombol pilih tema & pilih kota ada di AppBar
    expect(find.byIcon(Icons.brightness_6), findsOneWidget);
    expect(find.byIcon(Icons.menu), findsOneWidget);
  });
}
