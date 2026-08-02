/// Processing — a receipt for the last scan.
///
/// The app rewrites the user's own data: it drops things it decides aren't
/// real and renames others. Doing that invisibly is how an assistant loses
/// trust, so every correction is listed here in plain language, next to the
/// counts that produced it.
library;

import 'package:flutter/cupertino.dart';
import 'package:provider/provider.dart';

import '../../core/palette.dart';
import '../../domain/sync_report.dart';
import '../../state/app_controller.dart';
import '../format.dart';
import '../glass/glass.dart';

class ProcessingScreen extends StatelessWidget {
  const ProcessingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppController>();
    final report = app.lastReport;
    final busy = app.stage.isBusy;

    return GlassBackground(
      child: CupertinoPageScaffold(
        backgroundColor: const Color(0x00000000),
        navigationBar: const CupertinoNavigationBar(
          middle: Text('Processing'),
          backgroundColor: Color(0x00000000),
          border: null,
        ),
        child: SafeArea(
          child: ListView(
            padding: EdgeInsets.zero,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
                child: GlassCard(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          if (busy) ...[
                            const CupertinoActivityIndicator(),
                            const SizedBox(width: 10),
                          ],
                          Expanded(
                            child: Text(
                              busy ? app.stage.label : report.headline,
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w600,
                                height: 1.3,
                                letterSpacing: -0.2,
                                color: Palette.label(context),
                              ),
                            ),
                          ),
                        ],
                      ),
                      if (!report.neverSynced) ...[
                        const SizedBox(height: 6),
                        Text(
                          'Last scan ${formatDay(report.startedAt)} · '
                          'took ${_seconds(report.duration)}',
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
              _pipeline(context, app.stage),
              if (report.breakdown.isNotEmpty)
                GlassSection(
                  label: 'Extracted',
                  children: [
                    for (final line in report.breakdown)
                      GlassRow(
                        icon: CupertinoIcons.square_stack_3d_up,
                        title: line,
                      ),
                  ],
                ),
              GlassSection(
                label: 'AI audit',
                children: [
                  GlassRow(
                    icon: report.aiRan
                        ? CupertinoIcons.sparkles
                        : CupertinoIcons.circle,
                    title: report.aiRan ? 'Checked every insight' : 'Not used',
                    subtitle: report.aiError ??
                        (report.aiRan
                            ? '${report.aiCorrections} correction'
                                '${report.aiCorrections == 1 ? '' : 's'} '
                                'made to this scan'
                            : 'Turn AI on to have results double-checked'),
                    subtitleMaxLines: 2,
                  ),
                  for (final note in report.aiNotes)
                    GlassRow(
                      icon: CupertinoIcons.wand_stars,
                      iconTint: Palette.accent(context),
                      title: note,
                      titleMaxLines: 2,
                    ),
                ],
              ),
              const Footnote(
                'Corrections apply to the stored insights, never to your '
                'mail. Nothing in your Gmail is modified — the scope is '
                'read-only.',
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  static String _seconds(Duration duration) {
    final seconds = duration.inMilliseconds / 1000;
    return seconds < 10
        ? '${seconds.toStringAsFixed(1)}s'
        : '${duration.inSeconds}s';
  }

  /// The pipeline as a checklist, so a running scan shows where it is.
  Widget _pipeline(BuildContext context, SyncStage current) {
    const stages = [
      SyncStage.fetching,
      SyncStage.extracting,
      SyncStage.auditing,
      SyncStage.saving,
    ];
    final currentIndex = stages.indexOf(current);
    final finished = current == SyncStage.done;

    return GlassSection(
      label: 'Pipeline',
      children: [
        for (var i = 0; i < stages.length; i++)
          GlassRow(
            icon: finished || (currentIndex >= 0 && i < currentIndex)
                ? CupertinoIcons.checkmark_circle_fill
                : (i == currentIndex
                    ? CupertinoIcons.circle_lefthalf_fill
                    : CupertinoIcons.circle),
            iconTint: i == currentIndex && !finished
                ? Palette.accent(context)
                : null,
            title: stages[i].label,
          ),
      ],
    );
  }
}
