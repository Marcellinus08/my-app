import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teman_arah/utils/app_feedback.dart';

void main() {
  testWidgets('feedback production menampilkan pesan ramah pengguna', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    late BuildContext pageContext;

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            pageContext = context;
            return const Scaffold(body: Text('Halaman uji'));
          },
        ),
      ),
    );

    AppFeedback.show(
      pageContext,
      'Izin lokasi diperlukan untuk memulai navigasi.',
      type: AppFeedbackType.warning,
    );
    await tester.pump();

    expect(
      find.text('Izin lokasi diperlukan untuk memulai navigasi.'),
      findsOneWidget,
    );
    final semanticLabels = tester
        .widgetList<Semantics>(find.byType(Semantics))
        .map((widget) => widget.properties.label);
    expect(
      semanticLabels,
      contains('Izin lokasi diperlukan untuk memulai navigasi.'),
    );
    semantics.dispose();
  });
}
