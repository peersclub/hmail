/// Full-screen first-scan reveal — giant number, almost nothing else.
library;

import 'dart:ui' as ui;

import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/palette.dart';
import '../../domain/backfill_stats.dart';
import '../../state/app_controller.dart';
import '../glass/glass.dart';

class MoneyShotScreen extends StatefulWidget {
  const MoneyShotScreen({super.key});

  @override
  State<MoneyShotScreen> createState() => _MoneyShotScreenState();
}

class _MoneyShotScreenState extends State<MoneyShotScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _enter = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 500),
  );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      HapticFeedback.lightImpact();
      if (!mounted) return;
      if (MediaQuery.disableAnimationsOf(context)) {
        _enter.value = 1;
      } else {
        _enter.forward();
      }
    });
  }

  @override
  void dispose() {
    _enter.dispose();
    super.dispose();
  }

  void _dismiss() {
    context.read<AppController>().dismissMoneyShot();
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final stats = context.watch<AppController>().backfillStats;
    final reduced = MediaQuery.disableAnimationsOf(context);
    final annual =
        stats.annualRecurringByCurrency[stats.dominantCurrency] ?? 0;
    final hasMoney = stats.subscriptionCount > 0 && annual > 0;

    return CupertinoPageScaffold(
      backgroundColor: const Color(0x00000000),
      child: GlassBackground(
        child: ReadableWidth(
          child: SafeArea(
            child: AnimatedBuilder(
              animation: _enter,
              builder: (context, _) {
                final t = Curves.easeOutCubic.transform(_enter.value);
                final late = Curves.easeOut.transform(
                  ((_enter.value - 0.35) / 0.65).clamp(0.0, 1.0),
                );
                return Opacity(
                  opacity: t,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(28, 8, 28, 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Align(
                          alignment: Alignment.centerRight,
                          child: Semantics(
                            button: true,
                            label: 'Dismiss',
                            child: CupertinoButton(
                              padding: const EdgeInsets.all(8),
                              onPressed: _dismiss,
                              child: Icon(
                                CupertinoIcons.xmark,
                                size: 22,
                                color: Palette.secondaryLabel(context),
                              ),
                            ),
                          ),
                        ),
                        const Spacer(flex: 2),
                        Text(
                          'HIDING IN YOUR INBOX',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 1.2,
                            color: Palette.secondaryLabel(context),
                          ),
                        ),
                        const SizedBox(height: 16),
                        if (hasMoney)
                          Transform.translate(
                            offset: Offset(0, 24 * (1 - t)),
                            child: _CountUp(
                              amount: annual,
                              currency: stats.dominantCurrency,
                              reduced: reduced,
                            ),
                          )
                        else
                          Text(
                            'Found.',
                            style: TextStyle(
                              fontSize: 64,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -2.0,
                              color: Palette.label(context),
                            ),
                          ),
                        const SizedBox(height: 20),
                        Opacity(
                          opacity: late,
                          child: Transform.translate(
                            offset: Offset(0, 12 * (1 - late)),
                            child: Text(
                              stats.headline,
                              style: TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.w500,
                                height: 1.35,
                                letterSpacing: -0.4,
                                color: Palette.label(context),
                              ),
                            ),
                          ),
                        ),
                        if (_hasSecondary(stats)) ...[
                          const SizedBox(height: 28),
                          Opacity(
                            opacity: late,
                            child: Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                if (stats.upcomingBillsCount > 0)
                                  _Meta(
                                    '${stats.upcomingBillsCount} bills due',
                                  ),
                                if (stats.activeDeliveryCount > 0)
                                  _Meta(
                                    '${stats.activeDeliveryCount} packages',
                                  ),
                                if (stats.meetingsThisWeekCount > 0)
                                  _Meta(
                                    '${stats.meetingsThisWeekCount} meetings',
                                  ),
                              ],
                            ),
                          ),
                        ],
                        const Spacer(flex: 3),
                        Opacity(
                          opacity: late,
                          child: AccentButton(
                            'Show my Today',
                            onPressed: _dismiss,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  bool _hasSecondary(BackfillStats stats) =>
      stats.upcomingBillsCount > 0 ||
      stats.activeDeliveryCount > 0 ||
      stats.meetingsThisWeekCount > 0;
}

class _CountUp extends StatelessWidget {
  final double amount;
  final String currency;
  final bool reduced;

  const _CountUp({
    required this.amount,
    required this.currency,
    required this.reduced,
  });

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: reduced ? amount : 0, end: amount),
      duration: reduced ? Duration.zero : const Duration(milliseconds: 480),
      curve: Curves.easeOutCubic,
      builder: (context, value, _) {
        final symbol = switch (currency) {
          'INR' => '₹',
          'USD' => '\$',
          'EUR' => '€',
          'GBP' => '£',
          _ => '$currency ',
        };
        final rounded = value.round().toString();
        final grouped = rounded.replaceAllMapped(
          RegExp(r'(\d)(?=(\d{3})+(?!\d))'),
          (m) => '${m[1]},',
        );
        return Text.rich(
          TextSpan(
            children: [
              TextSpan(
                text: '$symbol$grouped',
                style: TextStyle(
                  fontSize: 64,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -2.2,
                  height: 1.0,
                  color: Palette.label(context),
                  fontFeatures: const [ui.FontFeature.tabularFigures()],
                ),
              ),
              TextSpan(
                text: '/yr',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w600,
                  letterSpacing: -0.6,
                  color: Palette.secondaryLabel(context),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _Meta extends StatelessWidget {
  final String label;

  const _Meta(this.label);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Palette.badgeFill(context),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w500,
          color: Palette.label(context),
        ),
      ),
    );
  }
}
