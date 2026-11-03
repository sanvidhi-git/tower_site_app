import 'package:flutter_test/flutter_test.dart';
import 'package:sanvidhi_site/core/format.dart';
import 'package:sanvidhi_site/services/outbox.dart';

void main() {
  test('outbox item round-trips through JSON and lists its photos', () {
    final item = OutboxItem(
      ref: 'abc',
      kind: OutboxKind.dailyReport,
      site: 'IN-3613941',
      title: 'Excavation',
      created: DateTime(2026, 11, 3, 10),
      payload: {
        'photos': [
          {'path': '/x/1.jpg', 'caption': 'pit'}
        ],
        'expenses': [
          {'expense_type': 'Labour Wages', 'amount': 500, 'bill_path': '/x/2.jpg'}
        ],
      },
    );
    final back = OutboxItem.fromJson(item.toJson());
    expect(back.ref, 'abc');
    expect(back.kind, OutboxKind.dailyReport);
    expect(back.photoPaths, ['/x/1.jpg', '/x/2.jpg']);
  });

  test('quantity formatting', () {
    expect(qty(12.0), '12');
    expect(qty(12.5), '12.5');
    expect(isoDate(DateTime(2026, 1, 5)), '2026-01-05');
  });
}
