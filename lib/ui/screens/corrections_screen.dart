/// Corrections — everything the user has told NoMail it got wrong.
///
/// The counterpart to [KnowledgeScreen]: that screen lists what the app taught
/// itself, this one lists where the user overruled it. Both exist for the same
/// reason — an app that quietly decides what to show you has to be able to
/// show you what it decided, and let you take it back.
library;

import 'package:flutter/cupertino.dart';
import 'package:provider/provider.dart';

import '../../core/palette.dart';
import '../../state/app_controller.dart';
import '../format.dart';
import '../glass/glass.dart';

class CorrectionsScreen extends StatelessWidget {
  const CorrectionsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppController>();
    final rules = app.ignores.rules;

    return GlassBackground(
      child: CupertinoPageScaffold(
        backgroundColor: const Color(0x00000000),
        navigationBar: const CupertinoNavigationBar(
          middle: Text('Corrections'),
          backgroundColor: Color(0x00000000),
          border: null,
        ),
        child: ReadableWidth(
          child: SafeArea(
            child: ListView(
              padding: EdgeInsets.zero,
              children: [
                if (rules.isEmpty)
                  const GlassEmptyState(
                    icon: CupertinoIcons.hand_thumbsdown,
                    title: 'Nothing Hidden',
                    caption:
                        'When NoMail reads something wrong — a release note as a '
                        'package, a newsletter as a bill — tap it and choose '
                        '"Not a package". It stops appearing, and lands here.',
                  )
                else
                  GlassSection(
                    label: 'Hidden',
                    children: [
                      for (final rule in rules)
                        GlassRow(
                          icon: CupertinoIcons.eye_slash,
                          title: rule.label,
                          titleMaxLines: 2,
                          subtitle: 'Since ${formatDay(rule.at)}',
                          trailingCaption: 'Undo',
                          trailingCaptionColor: Palette.accent(context),
                          onTap: () => app.unignore(rule.key),
                        ),
                    ],
                  ),
                const Footnote(
                  'Corrections hide insights, they never delete mail — and '
                  'nothing was thrown away, so undoing one brings its insights '
                  'straight back without another scan.',
                ),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
