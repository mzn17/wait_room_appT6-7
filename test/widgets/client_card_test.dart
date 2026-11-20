import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:waiting_room/models/client.dart';
import 'package:waiting_room/models/sync_status.dart';
import 'package:waiting_room/widgets/client_card.dart';
import 'package:waiting_room/widgets/queue_empty_widget.dart';

Widget wrap(Widget w) => MaterialApp(home: Scaffold(body: w));

void main() {
  testWidgets('official client shows its queue number', (t) async {
    await t.pumpWidget(wrap(ClientCard(
        client: Client(
            id: '1', name: 'Ali', queueNumber: 5, createdAt: DateTime(2026)))));
    expect(find.text('Ali'), findsOneWidget);
    expect(find.text('5'), findsOneWidget);
  });

  testWidgets('pending client shows waiting-to-sync text', (t) async {
    await t.pumpWidget(wrap(ClientCard(
        client: Client(
            id: '1',
            name: 'Sara',
            createdAt: DateTime(2026),
            syncStatus: SyncStatus.pending))));
    expect(find.textContaining('Waiting to sync'), findsOneWidget);
  });

  testWidgets('own registration shows a You badge', (t) async {
    await t.pumpWidget(wrap(ClientCard(
        isMine: true,
        client: Client(
            id: '1',
            name: 'Ali',
            registeredBy: 'user-1',
            createdAt: DateTime(2026)))));
    expect(find.text('You'), findsOneWidget);
  });

  testWidgets('empty widget shows message', (t) async {
    await t.pumpWidget(wrap(const QueueEmptyWidget()));
    expect(find.text('The waiting queue is empty'), findsOneWidget);
  });
}
