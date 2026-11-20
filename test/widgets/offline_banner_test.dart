import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waiting_room/models/app_connectivity.dart';
import 'package:waiting_room/widgets/offline_banner.dart';

Widget wrap(Widget w) => MaterialApp(home: Scaffold(body: w));

void main() {
  testWidgets('shows message when offline', (t) async {
    await t
        .pumpWidget(wrap(const OfflineBanner(status: AppConnectivity.offline)));
    expect(find.text('No network connection'), findsOneWidget);
  });

  testWidgets('shows message when backend unavailable', (t) async {
    await t.pumpWidget(
        wrap(const OfflineBanner(status: AppConnectivity.backendUnavailable)));
    expect(find.text('Waiting-room server unavailable'), findsOneWidget);
  });

  testWidgets('is hidden when online', (t) async {
    await t
        .pumpWidget(wrap(const OfflineBanner(status: AppConnectivity.online)));
    expect(find.byType(Text), findsNothing);
  });
}
