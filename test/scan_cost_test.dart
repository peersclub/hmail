import 'package:flutter_test/flutter_test.dart';
import 'package:hmail/domain/scan_cost.dart';
import 'package:hmail/domain/scan_settings.dart';

/// Roughly Haiku-class pricing, in OpenRouter's own units (USD per token).
const _haiku = ModelPricing(
  promptUsdPerToken: 0.000001,
  completionUsdPerToken: 0.000005,
);

void main() {
  group('ModelPricing.fromJson', () {
    test('parses the string rates OpenRouter actually sends', () {
      final pricing = ModelPricing.fromJson({
        'prompt': '0.000001',
        'completion': '0.000005',
      });
      expect(pricing, isNotNull);
      expect(pricing!.promptUsdPerToken, 0.000001);
      expect(pricing.completionUsdPerToken, 0.000005);
      expect(pricing.isPriced, isTrue);
    });

    test('accepts numbers too', () {
      final pricing = ModelPricing.fromJson({
        'prompt': 1e-6,
        'completion': 5e-6,
      });
      expect(pricing?.promptUsdPerToken, 1e-6);
    });

    test('a free model parses but is not priced', () {
      final pricing = ModelPricing.fromJson({'prompt': '0', 'completion': '0'});
      expect(pricing, isNotNull);
      expect(pricing!.isPriced, isFalse);
    });

    test('anything unexpected is null, never a guessed price', () {
      expect(ModelPricing.fromJson(null), isNull);
      expect(ModelPricing.fromJson('cheap'), isNull);
      expect(ModelPricing.fromJson({'prompt': 'free'}), isNull);
      expect(ModelPricing.fromJson({'prompt': '0.1'}), isNull);
      // -1 is how OpenRouter marks "priced elsewhere".
      expect(
        ModelPricing.fromJson({'prompt': '-1', 'completion': '-1'}),
        isNull,
      );
    });
  });

  group('estimateScanCost', () {
    test('reports scope with no money when pricing is unavailable', () {
      final estimate = estimateScanCost(settings: const ScanSettings());
      expect(estimate.emails, const ScanSettings().estimatedMaxEmails);
      expect(estimate.hasPrice, isFalse);
      expect(estimate.priceLine, isNull);
      expect(estimate.summary, contains('AI cost unknown'));
    });

    test('an unpriced model yields no estimate either', () {
      final estimate = estimateScanCost(
        settings: const ScanSettings(),
        pricing: const ModelPricing(
          promptUsdPerToken: 0,
          completionUsdPerToken: 0,
        ),
      );
      expect(estimate.hasPrice, isFalse);
    });

    test('AI off costs exactly nothing, and says so', () {
      final estimate = estimateScanCost(
        settings: const ScanSettings(aiEnabled: false),
        pricing: _haiku,
      );
      expect(estimate.lowUsd, 0);
      expect(estimate.highUsd, 0);
    });

    test('the range is ordered and the low end is genuinely lower', () {
      final estimate = estimateScanCost(
        settings: const ScanSettings(),
        pricing: _haiku,
      );
      expect(estimate.hasPrice, isTrue);
      expect(estimate.lowUsd, lessThan(estimate.highUsd!));
      expect(estimate.lowUsd, greaterThan(0));
    });

    test('a Haiku-class scan lands in cents, not dollars', () {
      // Sanity anchor: if a routine scan ever estimates above a dollar, either
      // the coefficients or the prompt caps have drifted badly.
      final estimate = estimateScanCost(
        settings: const ScanSettings(),
        pricing: _haiku,
      );
      expect(estimate.highUsd, lessThan(1.0));
    });

    test('reading more mail costs more', () {
      final small = estimateScanCost(
        settings: const ScanSettings(maxEmailsPerQuery: 10),
        pricing: _haiku,
      );
      final big = estimateScanCost(
        settings: const ScanSettings(maxEmailsPerQuery: 100),
        pricing: _haiku,
      );
      expect(big.emails, greaterThan(small.emails));
      expect(big.highUsd, greaterThan(small.highUsd!));
    });

    test('switching a domain off reads less mail and costs less', () {
      final all = estimateScanCost(
        settings: const ScanSettings(),
        pricing: _haiku,
      );
      final fewer = estimateScanCost(
        settings: const ScanSettings(
          scanReads: false,
          scanTravel: false,
          scanDiscovery: false,
        ),
        pricing: _haiku,
      );
      expect(fewer.emails, lessThan(all.emails));
      expect(fewer.highUsd, lessThan(all.highUsd!));
    });

    test('a costlier model costs more for the same scan', () {
      const opus = ModelPricing(
        promptUsdPerToken: 0.000015,
        completionUsdPerToken: 0.000075,
      );
      final cheap = estimateScanCost(
        settings: const ScanSettings(),
        pricing: _haiku,
      );
      final dear = estimateScanCost(
        settings: const ScanSettings(),
        pricing: opus,
      );
      expect(dear.highUsd, greaterThan(cheap.highUsd!));
    });

    test('skipping the learner lowers the ceiling', () {
      final withLearner = estimateScanCost(
        settings: const ScanSettings(),
        pricing: _haiku,
      );
      final without = estimateScanCost(
        settings: const ScanSettings(),
        pricing: _haiku,
        learnerRuns: false,
      );
      expect(without.highUsd, lessThan(withLearner.highUsd!));
    });

    test('scanning nothing estimates nothing', () {
      final estimate = estimateScanCost(
        settings: const ScanSettings(
          scanMoney: false,
          scanDeliveries: false,
          scanEvents: false,
          scanReads: false,
          scanTravel: false,
          scanDiscovery: false,
        ),
        pricing: _haiku,
      );
      expect(estimate.emails, 0);
      expect(estimate.hasPrice, isFalse);
    });
  });

  group('wording', () {
    test('a sub-cent estimate never renders as zero dollars', () {
      const nearlyFree = ModelPricing(
        promptUsdPerToken: 1e-9,
        completionUsdPerToken: 1e-9,
      );
      final estimate = estimateScanCost(
        settings: const ScanSettings(),
        pricing: nearlyFree,
      );
      expect(estimate.priceLine, 'Under a cent of AI per scan');
      expect(estimate.priceLine, isNot(contains('0.00')));
    });

    test('a real estimate states a range per scan', () {
      const dear = ModelPricing(
        promptUsdPerToken: 0.0001,
        completionUsdPerToken: 0.0005,
      );
      final estimate = estimateScanCost(
        settings: const ScanSettings(),
        pricing: dear,
      );
      expect(estimate.priceLine, startsWith('About \$'));
      expect(estimate.priceLine, contains('–'));
      expect(estimate.priceLine, endsWith('per scan'));
    });

    test('the row summary carries both scope and cost', () {
      final estimate = estimateScanCost(
        settings: const ScanSettings(),
        pricing: _haiku,
      );
      expect(estimate.summary, contains('emails per scan'));
      expect(estimate.summary.toLowerCase(), contains('ai'));
    });
  });
}
