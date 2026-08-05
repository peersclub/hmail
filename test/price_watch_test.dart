import 'package:flutter_test/flutter_test.dart';
import 'package:hmail/data/store/insight_store.dart';
import 'package:hmail/data/sync/sync_engine.dart';
import 'package:hmail/data/ai/insight_ai.dart';
import 'package:hmail/domain/actions.dart';
import 'package:hmail/domain/insight.dart';
import 'package:hmail/domain/insight_mapper.dart';
import 'package:hmail/domain/models.dart';
import 'package:hmail/domain/price_watch.dart';

/// A fixed clock so every expectation is exact.
final _now = DateTime(2026, 8, 5, 10);

Subscription _sub({
  String service = 'Netflix',
  double amount = 649,
  String currency = 'INR',
  Cadence cadence = Cadence.monthly,
  DateTime? lastSeen,
  String sourceEmailId = 'e1',
  String? manageUrl,
}) =>
    Subscription(
      service: service,
      amount: amount,
      currency: currency,
      cadence: cadence,
      lastSeen: lastSeen ?? _now,
      sourceEmailId: sourceEmailId,
      manageUrl: manageUrl,
    );

PriceChange _change({
  String service = 'Netflix',
  double oldAmount = 649,
  double newAmount = 699,
  String currency = 'INR',
  Cadence cadence = Cadence.monthly,
  DateTime? detectedAt,
  String sourceEmailId = 'e2',
}) =>
    PriceChange(
      service: service,
      oldAmount: oldAmount,
      newAmount: newAmount,
      currency: currency,
      cadence: cadence,
      detectedAt: detectedAt ?? _now,
      sourceEmailId: sourceEmailId,
    );

void main() {
  group('detectPriceChanges', () {
    test('catches a straightforward hike', () {
      final changes = detectPriceChanges(
        previous: [_sub(amount: 649, sourceEmailId: 'old')],
        fresh: [
          _sub(
            amount: 699,
            sourceEmailId: 'new',
            lastSeen: _now.add(const Duration(days: 30)),
          )
        ],
        now: _now,
      );

      expect(changes, hasLength(1));
      expect(changes.single.service, 'Netflix');
      expect(changes.single.oldAmount, 649);
      expect(changes.single.newAmount, 699);
      expect(changes.single.isIncrease, isTrue);
      expect(changes.single.monthlyDelta, 50);
      expect(changes.single.detectedAt, _now);
    });

    test('catches a drop, and reports it as one', () {
      final changes = detectPriceChanges(
        previous: [_sub(amount: 699, sourceEmailId: 'old')],
        fresh: [
          _sub(
            amount: 649,
            sourceEmailId: 'new',
            lastSeen: _now.add(const Duration(days: 30)),
          )
        ],
        now: _now,
      );

      expect(changes.single.isIncrease, isFalse);
      expect(changes.single.monthlyDelta, -50);
    });

    test('a yearly plan reports monthly impact, not the raw delta', () {
      final changes = detectPriceChanges(
        previous: [
          _sub(amount: 6000, cadence: Cadence.yearly, sourceEmailId: 'old')
        ],
        fresh: [
          _sub(
            amount: 7200,
            cadence: Cadence.yearly,
            sourceEmailId: 'new',
            lastSeen: _now.add(const Duration(days: 365)),
          )
        ],
        now: _now,
      );

      expect(changes.single.monthlyDelta, 100);
    });

    test('a brand new subscription is not a change', () {
      final changes = detectPriceChanges(
        previous: [_sub(service: 'Spotify')],
        fresh: [_sub(service: 'Spotify'), _sub(service: 'Netflix')],
        now: _now,
      );
      expect(changes, isEmpty);
    });

    test('an unchanged price produces nothing', () {
      final changes = detectPriceChanges(
        previous: [_sub(sourceEmailId: 'old')],
        fresh: [
          _sub(
            sourceEmailId: 'new',
            lastSeen: _now.add(const Duration(days: 30)),
          )
        ],
        now: _now,
      );
      expect(changes, isEmpty);
    });

    group('guards against false hikes', () {
      test('the same source email re-extracted is not a change', () {
        // An extractor fix changing what one email yields must never look
        // like the merchant raising a price.
        final changes = detectPriceChanges(
          previous: [_sub(amount: 649, sourceEmailId: 'same')],
          fresh: [
            _sub(
              amount: 699,
              sourceEmailId: 'same',
              lastSeen: _now.add(const Duration(days: 1)),
            )
          ],
          now: _now,
        );
        expect(changes, isEmpty);
      });

      test('older evidence never rewrites the price', () {
        // A backfilled receipt from last year arriving today carries an old
        // amount; treating it as "new" would invent a hike backwards.
        final changes = detectPriceChanges(
          previous: [
            _sub(
              amount: 699,
              sourceEmailId: 'recent',
              lastSeen: _now,
            )
          ],
          fresh: [
            _sub(
              amount: 649,
              sourceEmailId: 'ancient',
              lastSeen: _now.subtract(const Duration(days: 400)),
            )
          ],
          now: _now,
        );
        expect(changes, isEmpty);
      });

      test('a different currency is a different product, not a hike', () {
        final changes = detectPriceChanges(
          previous: [_sub(amount: 649, currency: 'INR', sourceEmailId: 'old')],
          fresh: [
            _sub(
              amount: 8.99,
              currency: 'USD',
              sourceEmailId: 'new',
              lastSeen: _now.add(const Duration(days: 30)),
            )
          ],
          now: _now,
        );
        expect(changes, isEmpty);
      });

      test('monthly against yearly is a plan switch, not a hike', () {
        final changes = detectPriceChanges(
          previous: [
            _sub(amount: 649, cadence: Cadence.monthly, sourceEmailId: 'old')
          ],
          fresh: [
            _sub(
              amount: 6490,
              cadence: Cadence.yearly,
              sourceEmailId: 'new',
              lastSeen: _now.add(const Duration(days: 30)),
            )
          ],
          now: _now,
        );
        expect(changes, isEmpty);
      });

      test('sub-1% wobble is rounding, not a price move', () {
        final changes = detectPriceChanges(
          previous: [_sub(amount: 649, sourceEmailId: 'old')],
          fresh: [
            _sub(
              amount: 652,
              sourceEmailId: 'new',
              lastSeen: _now.add(const Duration(days: 30)),
            )
          ],
          now: _now,
        );
        expect(changes, isEmpty);
      });

      test('1% or more clears the floor', () {
        final changes = detectPriceChanges(
          previous: [_sub(amount: 649, sourceEmailId: 'old')],
          fresh: [
            _sub(
              amount: 656,
              sourceEmailId: 'new',
              lastSeen: _now.add(const Duration(days: 30)),
            )
          ],
          now: _now,
        );
        expect(changes, hasLength(1));
      });

      test('a cheap plan still needs a real minor-unit move', () {
        // $0.99 → $0.995 is 0.5% and half a cent: both floors reject it.
        final changes = detectPriceChanges(
          previous: [
            _sub(amount: 0.99, currency: 'USD', sourceEmailId: 'old')
          ],
          fresh: [
            _sub(
              amount: 0.995,
              currency: 'USD',
              sourceEmailId: 'new',
              lastSeen: _now.add(const Duration(days: 30)),
            )
          ],
          now: _now,
        );
        expect(changes, isEmpty);
      });

      test('a zero old amount is failed extraction, not a base price', () {
        final changes = detectPriceChanges(
          previous: [_sub(amount: 0, sourceEmailId: 'old')],
          fresh: [
            _sub(
              amount: 699,
              sourceEmailId: 'new',
              lastSeen: _now.add(const Duration(days: 30)),
            )
          ],
          now: _now,
        );
        expect(changes, isEmpty);
      });

      test('empty either side is a no-op', () {
        expect(detectPriceChanges(previous: [], fresh: [_sub()]), isEmpty);
        expect(detectPriceChanges(previous: [_sub()], fresh: []), isEmpty);
      });
    });

    test('collapses duplicates the way the store merge does', () {
      // Two receipts for one service in a single sync: the newest wins, so the
      // reported new price is the one the Money tab will show.
      final changes = detectPriceChanges(
        previous: [_sub(amount: 649, sourceEmailId: 'old')],
        fresh: [
          _sub(
            amount: 679,
            sourceEmailId: 'mid',
            lastSeen: _now.add(const Duration(days: 10)),
          ),
          _sub(
            amount: 699,
            sourceEmailId: 'newest',
            lastSeen: _now.add(const Duration(days: 30)),
          ),
        ],
        now: _now,
      );

      expect(changes, hasLength(1));
      expect(changes.single.newAmount, 699);
      expect(changes.single.sourceEmailId, 'newest');
    });

    test('orders by monthly impact, biggest first', () {
      final changes = detectPriceChanges(
        previous: [
          _sub(service: 'Netflix', amount: 649, sourceEmailId: 'n-old'),
          _sub(service: 'Spotify', amount: 119, sourceEmailId: 's-old'),
        ],
        fresh: [
          _sub(
            service: 'Netflix',
            amount: 669,
            sourceEmailId: 'n-new',
            lastSeen: _now.add(const Duration(days: 30)),
          ),
          _sub(
            service: 'Spotify',
            amount: 179,
            sourceEmailId: 's-new',
            lastSeen: _now.add(const Duration(days: 30)),
          ),
        ],
        now: _now,
      );

      expect([for (final c in changes) c.service], ['Spotify', 'Netflix']);
    });
  });

  group('mergePriceChanges', () {
    test('keeps stored history and adds new detections', () {
      final merged = mergePriceChanges(
        [_change(service: 'Spotify', newAmount: 179)],
        [_change(service: 'Netflix', newAmount: 699)],
      );
      expect(merged, hasLength(2));
    });

    test('drops stale entries', () {
      final old = _change(
        detectedAt: DateTime.now().subtract(const Duration(days: 120)),
      );
      expect(mergePriceChanges([old], []), isEmpty);
    });

    test('a re-detection of the same move refreshes rather than duplicates',
        () {
      final first = _change(detectedAt: DateTime.now());
      final again = _change(
        detectedAt: DateTime.now().add(const Duration(days: 1)),
      );
      final merged = mergePriceChanges([first], [again]);
      expect(merged, hasLength(1));
      expect(merged.single.detectedAt, again.detectedAt);
    });

    test('a second hike on the same service is its own entry', () {
      // 649 → 699 then 699 → 749 are two distinct events; the dedupe key is
      // service + new amount precisely so the later one does not erase the
      // earlier.
      final merged = mergePriceChanges(
        [_change(oldAmount: 649, newAmount: 699)],
        [_change(oldAmount: 699, newAmount: 749)],
      );
      expect(merged, hasLength(2));
    });

    test('newest first', () {
      final merged = mergePriceChanges([], [
        _change(
          service: 'Old',
          detectedAt: DateTime.now().subtract(const Duration(days: 10)),
        ),
        _change(service: 'New', detectedAt: DateTime.now()),
      ]);
      expect([for (final c in merged) c.service], ['New', 'Old']);
    });
  });

  group('priceDriftByCurrency', () {
    test('nets rises against drops, per currency', () {
      final drift = priceDriftByCurrency([
        _change(service: 'Netflix', oldAmount: 649, newAmount: 699),
        _change(service: 'Spotify', oldAmount: 179, newAmount: 119),
        _change(
          service: 'Notion',
          currency: 'USD',
          oldAmount: 8,
          newAmount: 10,
        ),
      ]);

      expect(drift['INR'], -10); // +50 and −60
      expect(drift['USD'], 2);
    });

    test('never mixes currencies into one number', () {
      final drift = priceDriftByCurrency([
        _change(currency: 'INR', oldAmount: 100, newAmount: 200),
        _change(currency: 'USD', oldAmount: 100, newAmount: 200),
      ]);
      expect(drift.keys, containsAll(['INR', 'USD']));
      expect(drift['INR'], 100);
    });
  });

  group('store merge', () {
    test('folds detected changes into the stored history', () {
      final store = InsightStore();
      final previous = InsightSnapshot(
        subscriptions: [_sub(amount: 649, sourceEmailId: 'old')],
        priceChanges: [_change(service: 'Spotify', newAmount: 179)],
      );
      final fresh = InsightSnapshot(
        subscriptions: [
          _sub(
            amount: 699,
            sourceEmailId: 'new',
            lastSeen: _now.add(const Duration(days: 30)),
          )
        ],
        priceChanges: [_change(service: 'Netflix', newAmount: 699)],
      );

      final merged = store.merge(previous, fresh);
      expect(merged.priceChanges, hasLength(2));
      // And the subscription itself collapsed to the new price, which is what
      // makes running the detector before merge mandatory.
      expect(merged.subscriptions.single.amount, 699);
    });
  });

  group('audit', () {
    test('a rejected subscription takes its price change with it', () {
      final snapshot = InsightSnapshot(
        subscriptions: [_sub(sourceEmailId: 'bad')],
        priceChanges: [_change(sourceEmailId: 'bad')],
      );
      final audited = applyVerdicts(
        snapshot,
        const InsightVerdicts(rejected: {'bad'}),
      );
      expect(audited.subscriptions, isEmpty);
      expect(audited.priceChanges, isEmpty);
    });

    test('a renamed subscription renames its price change too', () {
      final snapshot = InsightSnapshot(
        subscriptions: [_sub(service: 'NETFLIX.COM', sourceEmailId: 'e2')],
        priceChanges: [_change(service: 'NETFLIX.COM', sourceEmailId: 'e2')],
      );
      final audited = applyVerdicts(
        snapshot,
        const InsightVerdicts(renamed: {'e2': 'Netflix'}),
      );
      expect(audited.priceChanges.single.service, 'Netflix');
    });
  });

  group('mapper', () {
    test('a price change outranks an upcoming bill', () {
      final insights = rankInsights(snapshotToInsights(InsightSnapshot(
        priceChanges: [_change()],
        bills: [
          Bill(
            issuer: 'BESCOM',
            amount: 1840,
            currency: 'INR',
            dueDate: DateTime.now().add(const Duration(days: 20)),
            lastSeen: DateTime.now(),
            sourceEmailId: 'b1',
          )
        ],
      )));

      expect(insights.first.id, startsWith('price:'));
    });

    test('renders both prices and the monthly delta', () {
      final insight = snapshotToInsights(
        InsightSnapshot(priceChanges: [_change()]),
      ).single;

      expect(insight.title, 'Netflix');
      expect(insight.subtitle, contains('649'));
      expect(insight.subtitle, contains('699'));
      expect(insight.trailing, startsWith('+'));
      expect(insight.domain, InsightDomain.money);
      expect(insight.weight, 85);
    });

    test('a stale change never reaches the UI', () {
      final insights = snapshotToInsights(InsightSnapshot(
        priceChanges: [
          _change(
            detectedAt: DateTime.now().subtract(const Duration(days: 120)),
          )
        ],
      ));
      expect(insights, isEmpty);
    });
  });

  group('actionsForPriceChange', () {
    test('borrows the live subscription manage link', () {
      final actions = actionsForPriceChange(
        _change(),
        [_sub(manageUrl: 'https://netflix.com/account')],
      );
      expect(actions.first.kind, ActionKind.manage);
      expect(actions.first.uri.toString(), 'https://netflix.com/account');
    });

    test('falls back to the registry when the email carried no link', () {
      final actions = actionsForPriceChange(_change(), [_sub()]);
      expect(actions.first.kind, ActionKind.manage);
    });

    test('always ends with the open-email floor', () {
      final actions = actionsForPriceChange(
        _change(service: 'Some Unknown Service'),
        const [],
      );
      expect(actions.last.kind, ActionKind.openEmail);
    });
  });
}
