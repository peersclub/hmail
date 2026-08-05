/// Scan settings — how much mail NoMail is allowed to read.
///
/// Two reasons this is user-controlled rather than a constant: reading less
/// is a privacy choice, and reading more costs real money once the AI pass
/// runs over it. The estimate at the top makes both consequences visible
/// before the next sync, not after.
library;

import 'package:flutter/cupertino.dart';
import 'package:provider/provider.dart';

import '../../core/palette.dart';
import '../../domain/scan_cost.dart';
import '../../domain/scan_settings.dart';
import '../../state/app_controller.dart';
import '../glass/glass.dart';

class ScanScreen extends StatefulWidget {
  const ScanScreen({super.key});

  @override
  State<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends State<ScanScreen> {
  /// Null until the catalog answers, and permanently null when it can't be
  /// reached — the estimate then shows scope without a price rather than a
  /// made-up one.
  ModelPricing? _pricing;

  @override
  void initState() {
    super.initState();
    _loadPricing();
  }

  Future<void> _loadPricing() async {
    final app = context.read<AppController>();
    final pricing = await app.aiStatus.fetchPricing(app.settings.aiModel);
    if (!mounted) return;
    setState(() => _pricing = pricing);
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppController>();
    final settings = app.settings;
    final estimate = estimateScanCost(settings: settings, pricing: _pricing);

    Future<void> update(ScanSettings next) => app.updateSettings(next);

    return GlassBackground(
      child: CupertinoPageScaffold(
        backgroundColor: const Color(0x00000000),
        navigationBar: const CupertinoNavigationBar(
          middle: Text('Scanning'),
          backgroundColor: Color(0x00000000),
          border: null,
        ),
        child: ReadableWidth(
          child: SafeArea(
            child: ListView(
              padding: EdgeInsets.zero,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
                  child: GlassCard(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      children: [
                        Text(
                          '${settings.estimatedMaxEmails}',
                          style: TextStyle(
                            fontSize: 40,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -1,
                            color: Palette.label(context),
                          ),
                        ),
                        Text(
                          'emails per scan, at most',
                          style: TextStyle(
                            fontSize: 14,
                            color: Palette.secondaryLabel(context),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          settings.describeScope,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 13,
                            height: 1.35,
                            color: Palette.secondaryLabel(context),
                          ),
                        ),
                        // The money line only appears once there is something
                        // true to say: with AI off there is no cost, and with
                        // pricing unreachable there is no number.
                        if (settings.aiEnabled && estimate.hasPrice) ...[
                          const SizedBox(height: 10),
                          Text(
                            estimate.priceLine!,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 13,
                              color: Palette.secondaryLabel(context),
                            ),
                          ),
                        ] else if (!settings.aiEnabled) ...[
                          const SizedBox(height: 10),
                          Text(
                            'AI is off — scans cost nothing',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 13,
                              color: Palette.secondaryLabel(context),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                _choiceSection(
                  context,
                  label: 'Emails per search',
                  caption: 'More coverage, slower scans and higher AI cost.',
                  options: ScanSettings.emailCountOptions,
                  selected: settings.maxEmailsPerQuery,
                  labelFor: (value) => '$value',
                  onSelect: (value) =>
                      update(settings.copyWith(maxEmailsPerQuery: value)),
                ),
                _choiceSection(
                  context,
                  label: 'How far back',
                  caption:
                      'Applies to receipts, so yearly renewals still surface. '
                      'Bills and packages always use their own short windows.',
                  options: ScanSettings.historyOptions,
                  selected: settings.historyDays,
                  labelFor: _historyLabel,
                  onSelect: (value) =>
                      update(settings.copyWith(historyDays: value)),
                ),
                GlassSection(
                  label: 'What to look for',
                  children: [
                    _switchRow(
                      context,
                      icon: CupertinoIcons.creditcard,
                      title: 'Money',
                      subtitle: 'Subscriptions and bills',
                      value: settings.scanMoney,
                      onChanged: (on) =>
                          update(settings.copyWith(scanMoney: on)),
                    ),
                    _switchRow(
                      context,
                      icon: CupertinoIcons.cube_box,
                      title: 'Packages',
                      subtitle: 'Orders and shipping updates',
                      value: settings.scanDeliveries,
                      onChanged: (on) =>
                          update(settings.copyWith(scanDeliveries: on)),
                    ),
                    _switchRow(
                      context,
                      icon: CupertinoIcons.calendar,
                      title: 'Meetings',
                      subtitle: 'Calendar invites and join links',
                      value: settings.scanEvents,
                      onChanged: (on) =>
                          update(settings.copyWith(scanEvents: on)),
                    ),
                  ],
                ),
                const Footnote(
                  'Changes apply on the next scan. Pull down on Today, or use '
                  'Rescan Everything to rebuild from scratch now.',
                ),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static String _historyLabel(int days) => switch (days) {
        90 => '3 months',
        180 => '6 months',
        365 => '1 year',
        730 => '2 years',
        _ => '$days days',
      };
}

/// Segmented picker inside a glass card.
Widget _choiceSection(
  BuildContext context, {
  required String label,
  required String caption,
  required List<int> options,
  required int selected,
  required String Function(int) labelFor,
  required ValueChanged<int> onSelect,
}) {
  return Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      SectionLabel(label),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: GlassCard(
          padding: const EdgeInsets.all(14),
          child: Column(
            children: [
              CupertinoSlidingSegmentedControl<int>(
                groupValue: selected,
                onValueChanged: (value) {
                  if (value != null) onSelect(value);
                },
                children: {
                  for (final option in options)
                    option: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Text(
                        labelFor(option),
                        style: const TextStyle(fontSize: 14),
                      ),
                    ),
                },
              ),
              const SizedBox(height: 10),
              Text(
                caption,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12,
                  height: 1.35,
                  color: Palette.secondaryLabel(context),
                ),
              ),
            ],
          ),
        ),
      ),
    ],
  );
}

Widget _switchRow(
  BuildContext context, {
  required IconData icon,
  required String title,
  required String subtitle,
  required bool value,
  required ValueChanged<bool> onChanged,
}) {
  return Padding(
    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
    child: Row(
      children: [
        IconBadge(icon),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontSize: 17,
                  letterSpacing: -0.4,
                  color: Palette.label(context),
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: TextStyle(
                  fontSize: 13,
                  color: Palette.secondaryLabel(context),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        CupertinoSwitch(value: value, onChanged: onChanged),
      ],
    ),
  );
}
