/// The daily summary, in full.
///
/// The brief card on Today is a glance: it caps the headline at four lines and
/// truncates, which meant a long summary was simply unreadable — the rest of it
/// existed and there was no way to reach it. This is where the card goes when
/// tapped, and it is deliberately the only surface in the app with no truncation
/// anywhere on it.
///
/// It also gathers the facts that make the summary trustworthy rather than
/// oracular: when it was written, whether a model wrote it or the rules did, how
/// much mail it was drawn from, and what the audit changed. A summary you cannot
/// interrogate is just an assertion.
library;

import 'package:flutter/cupertino.dart';
import 'package:provider/provider.dart';

import '../../core/palette.dart';
import '../../domain/models.dart';
import '../../state/app_controller.dart';
import '../format.dart';
import '../glass/glass.dart';
import 'processing_screen.dart';

class BriefScreen extends StatelessWidget {
  const BriefScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppController>();
    final brief = app.snapshot.brief;
    final byAi = app.lastReport.aiRan && !app.isDemo;

    return GlassBackground(
      child: CupertinoPageScaffold(
        backgroundColor: const Color(0x00000000),
        navigationBar: const CupertinoNavigationBar(
          middle: Text('Daily brief'),
          backgroundColor: Color(0x00000000),
          border: null,
        ),
        child: ReadableWidth(
          child: SafeArea(
            child: brief == null
                ? const _NoBrief()
                : _Brief(brief: brief, byAi: byAi, app: app),
          ),
        ),
      ),
    );
  }
}

class _Brief extends StatelessWidget {
  final DailyBrief brief;
  final bool byAi;
  final AppController app;

  const _Brief({required this.brief, required this.byAi, required this.app});

  @override
  Widget build(BuildContext context) {
    final snapshot = app.snapshot;
    final report = app.lastReport;

    return ListView(
      padding: EdgeInsets.zero,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 4),
          child: GlassCard(
            padding: const EdgeInsets.all(22),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // No maxLines: this screen exists precisely because the card
                // truncates.
                Text(
                  brief.headline,
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w600,
                    letterSpacing: -0.4,
                    height: 1.3,
                    color: Palette.label(context),
                  ),
                ),
                for (final bullet in brief.bullets) ...[
                  const SizedBox(height: 14),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(top: 9),
                        child: Container(
                          width: 4,
                          height: 4,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Palette.secondaryLabel(context),
                          ),
                        ),
                      ),
                      const SizedBox(width: 11),
                      Expanded(
                        child: Text(
                          bullet,
                          style: TextStyle(
                            fontSize: 16,
                            height: 1.45,
                            color: Palette.label(context),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),

        GlassSection(
          label: 'Where this came from',
          children: [
            GlassRow(
              icon: byAi ? CupertinoIcons.sparkles : CupertinoIcons.doc_text,
              title: byAi ? 'Written by AI' : 'Written by rules',
              // Naming the author matters: a rule-built brief is a summary of
              // what was extracted, an AI one is a judgement about it, and the
              // reader should know which they are holding.
              subtitle: byAi
                  ? 'A model read the extracted insights and wrote this'
                  : 'Built on this device from the extracted insights — '
                      'no AI involved',
              subtitleMaxLines: 3,
            ),
            GlassRow(
              icon: CupertinoIcons.clock,
              title: 'Written ${formatDay(brief.generatedAt)}',
              subtitle: _timeOf(brief.generatedAt),
            ),
            if (snapshot.lastSyncedAt != null)
              GlassRow(
                icon: CupertinoIcons.tray_full,
                title: '${snapshot.emailsScanned} emails read',
                subtitle: 'Last synced ${formatDay(snapshot.lastSyncedAt!)}',
                trailingCaption: 'Details',
                trailingCaptionColor: Palette.accent(context),
                onTap: () => Navigator.of(context, rootNavigator: true).push(
                  CupertinoPageRoute<void>(
                    builder: (_) => const ProcessingScreen(),
                  ),
                ),
              ),
            if (report.aiCorrections > 0)
              GlassRow(
                icon: CupertinoIcons.checkmark_shield,
                title: '${report.aiCorrections} corrected before this was '
                    'written',
                titleMaxLines: 2,
                subtitle: 'Insights the audit dropped or renamed, so the '
                    'summary is drawn from what survived',
                subtitleMaxLines: 3,
              ),
          ],
        ),

        _Counts(snapshot: snapshot),

        const Footnote(
          'The brief is rebuilt on every sync from whatever is in your inbox '
          'now, so there is one at a time — this is today\'s.',
        ),
        const SizedBox(height: 24),
      ],
    );
  }

  static String _timeOf(DateTime at) {
    final hour = at.hour % 12 == 0 ? 12 : at.hour % 12;
    final minute = at.minute.toString().padLeft(2, '0');
    return 'at $hour:$minute${at.hour < 12 ? 'am' : 'pm'}';
  }
}

/// What the brief was drawn from, by domain — the summary's own evidence.
class _Counts extends StatelessWidget {
  final InsightSnapshot snapshot;

  const _Counts({required this.snapshot});

  @override
  Widget build(BuildContext context) {
    final rows = <({IconData icon, String label, int count})>[
      (
        icon: CupertinoIcons.doc_text_fill,
        label: 'Bills due',
        count: snapshot.unpaidUpcoming.length
      ),
      (
        icon: CupertinoIcons.arrow_2_circlepath,
        label: 'Subscriptions',
        count: snapshot.subscriptions.length
      ),
      (
        icon: CupertinoIcons.cube_box_fill,
        label: 'Packages moving',
        count: snapshot.activeDeliveries.length
      ),
      (
        icon: CupertinoIcons.calendar,
        label: 'Meetings ahead',
        count: snapshot.upcomingEvents.length
      ),
      (
        icon: CupertinoIcons.lightbulb,
        label: 'Learned cards',
        count: snapshot.activeLearned.length
      ),
    ].where((r) => r.count > 0).toList();

    if (rows.isEmpty) return const SizedBox.shrink();

    return GlassSection(
      label: 'What it read',
      children: [
        for (final row in rows)
          GlassRow(
            icon: row.icon,
            title: row.label,
            trailing: '${row.count}',
          ),
      ],
    );
  }
}

class _NoBrief extends StatelessWidget {
  const _NoBrief();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: EdgeInsets.zero,
      children: const [
        GlassEmptyState(
          icon: CupertinoIcons.doc_text,
          title: 'No Brief Yet',
          caption:
              'The brief is written at the end of every sync. Run one and it '
              'will appear here — and at the top of Today.',
        ),
      ],
    );
  }
}
