import 'package:flutter_test/flutter_test.dart';
import 'package:hmail/data/store/settings_store.dart';
import 'package:hmail/domain/scan_settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('defaults', () {
    test('reproduce the original hardcoded scan behavior', () {
      const settings = ScanSettings();
      expect(settings.maxEmailsPerQuery, 25);
      expect(settings.historyDays, 365);
      expect(settings.scanMoney, isTrue);
      expect(settings.scanDeliveries, isTrue);
      expect(settings.scanEvents, isTrue);
      expect(settings.aiEnabled, isTrue);
      expect(settings.aiModel, 'anthropic/claude-haiku-4.5');
      expect(settings.briefHour, 8);
      expect(settings.scanReads, isTrue);
      // 5 Gmail queries x 25.
      expect(settings.estimatedMaxEmails, 150);
    });

    test('option lists match the values the UI offers', () {
      expect(ScanSettings.emailCountOptions, [25, 50, 100, 200]);
      expect(ScanSettings.historyOptions, [90, 180, 365, 730]);
    });
  });

  group('copyWith', () {
    test('preserves untouched fields', () {
      const settings = ScanSettings();
      final updated = settings.copyWith(maxEmailsPerQuery: 200);
      expect(updated.maxEmailsPerQuery, 200);
      expect(updated.historyDays, settings.historyDays);
      expect(updated.scanMoney, settings.scanMoney);
      expect(updated.scanDeliveries, settings.scanDeliveries);
      expect(updated.scanEvents, settings.scanEvents);
      expect(updated.aiEnabled, settings.aiEnabled);
      expect(updated.aiModel, settings.aiModel);
      expect(updated.briefHour, settings.briefHour);
    });

    test('can turn a domain and AI off without disturbing the rest', () {
      final updated = const ScanSettings()
          .copyWith(scanEvents: false, aiEnabled: false, briefHour: 21);
      expect(updated.scanEvents, isFalse);
      expect(updated.aiEnabled, isFalse);
      expect(updated.briefHour, 21);
      expect(updated.scanMoney, isTrue);
      expect(updated.scanDeliveries, isTrue);
    });
  });

  group('json', () {
    test('round-trips every field', () {
      const settings = ScanSettings(
        maxEmailsPerQuery: 100,
        historyDays: 730,
        scanMoney: false,
        scanDeliveries: true,
        scanEvents: false,
        aiEnabled: false,
        aiModel: 'anthropic/claude-sonnet-4.5',
        briefHour: 19,
      );
      expect(ScanSettings.fromJson(settings.toJson()), settings);
    });

    test('an empty map yields defaults', () {
      expect(ScanSettings.fromJson(const {}), const ScanSettings());
    });

    test('tolerates missing, unknown, and wrongly-typed keys', () {
      final settings = ScanSettings.fromJson(const {
        'maxEmailsPerQuery': 50,
        'scanDeliveries': false,
        'somethingFromTheFuture': 'ignored',
        'briefHour': 'not a number',
      });
      expect(settings.maxEmailsPerQuery, 50);
      expect(settings.scanDeliveries, isFalse);
      expect(settings.briefHour, 8); // fell back to the default
      expect(settings.historyDays, 365);
      expect(settings.aiModel, 'anthropic/claude-haiku-4.5');
    });
  });

  group('equality', () {
    test('identical settings are equal and hash alike', () {
      const a = ScanSettings(maxEmailsPerQuery: 50, briefHour: 7);
      const b = ScanSettings(maxEmailsPerQuery: 50, briefHour: 7);
      expect(a, b);
      expect(a.hashCode, b.hashCode);
    });

    test('a single changed field breaks equality', () {
      const base = ScanSettings();
      expect(base == base.copyWith(historyDays: 90), isFalse);
      expect(base == base.copyWith(scanMoney: false), isFalse);
      expect(base == base.copyWith(aiModel: 'other/model'), isFalse);
      expect(base.hashCode == base.copyWith(briefHour: 9).hashCode, isFalse);
    });
  });

  group('estimatedMaxEmails', () {
    test('all domains on counts money as two queries', () {
      expect(
        const ScanSettings(maxEmailsPerQuery: 50).estimatedMaxEmails,
        300,
      );
    });

    test('only deliveries is a single query', () {
      const settings = ScanSettings(
        maxEmailsPerQuery: 100,
        scanMoney: false,
        scanEvents: false,
        scanReads: false,
        scanTravel: false,
      );
      expect(settings.estimatedMaxEmails, 100);
    });

    test('money only is two queries, nothing selected is zero', () {
      const money = ScanSettings(
        maxEmailsPerQuery: 25,
        scanDeliveries: false,
        scanEvents: false,
        scanReads: false,
        scanTravel: false,
      );
      expect(money.estimatedMaxEmails, 50);

      const nothing = ScanSettings(
        scanMoney: false,
        scanDeliveries: false,
        scanEvents: false,
        scanReads: false,
        scanTravel: false,
      );
      expect(nothing.estimatedMaxEmails, 0);
    });
  });

  group('describeScope', () {
    test('all domains on with defaults', () {
      expect(
        const ScanSettings().describeScope,
        'Money, packages, meetings, reads and trips · up to 150 emails · 1 year of history',
      );
    });

    test('money only', () {
      const settings = ScanSettings(
        maxEmailsPerQuery: 50,
        historyDays: 730,
        scanDeliveries: false,
        scanEvents: false,
        scanReads: false,
        scanTravel: false,
      );
      expect(
        settings.describeScope,
        'Money · up to 100 emails · 2 years of history',
      );
    });

    test('two domains join with "and", and months read as months', () {
      const settings = ScanSettings(
        historyDays: 90,
        scanMoney: false,
        scanReads: false,
        scanTravel: false,
      );
      expect(
        settings.describeScope,
        'Packages and meetings · up to 50 emails · 3 months of history',
      );
    });

    test('nothing selected', () {
      const settings = ScanSettings(
        scanMoney: false,
        scanDeliveries: false,
        scanEvents: false,
        scanReads: false,
        scanTravel: false,
      );
      expect(settings.describeScope, 'Nothing selected');
    });
  });

  group('SettingsStore', () {
    test('load returns defaults when nothing is stored', () async {
      expect(await SettingsStore().load(), const ScanSettings());
    });

    test('save then load round-trips the settings', () async {
      final store = SettingsStore();
      const settings = ScanSettings(
        maxEmailsPerQuery: 200,
        historyDays: 180,
        scanEvents: false,
        aiEnabled: false,
        aiModel: 'anthropic/claude-sonnet-4.5',
        briefHour: 6,
      );
      await store.save(settings);
      expect(await store.load(), settings);
    });

    test('corrupt stored JSON falls back to defaults', () async {
      SharedPreferences.setMockInitialValues(
          {'scan_settings_v1': 'not json at all'});
      expect(await SettingsStore().load(), const ScanSettings());
    });

    test('clear forgets the stored settings', () async {
      final store = SettingsStore();
      await store.save(const ScanSettings(maxEmailsPerQuery: 100));
      await store.clear();
      expect(await store.load(), const ScanSettings());
    });
  });
}
