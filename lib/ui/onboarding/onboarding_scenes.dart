/// The three scenes of NoMail's first run.
///
/// Each scene is a self-contained animation that plays once when its page
/// becomes active and holds a slow idle afterwards, so a user who lingers has
/// something alive to look at and a user who swipes fast never waits.
///
/// ## Why these three
///
/// A first run has to leave the user knowing what the app *is*, or the polish
/// was decoration. So each scene demonstrates one real capability rather than
/// asserting a benefit: mail collapsing into insights, a price rise caught by
/// comparing two syncs, and a tap whose destination is named before you make
/// it. Nothing here claims a feature the app does not have.
///
/// ## The performance rules these obey
///
/// The previous carousel was janky for structural reasons, and every rule below
/// exists because breaking it cost frames:
///
///  * **No `BackdropFilter` anywhere in a scene.** `GlassCard` frosts its
///    background with a sigma-26 blur, which is fine for a still surface and
///    ruinous for one that moves: the blur re-samples what is behind it every
///    frame, and a page mid-swipe changes what is behind it every frame.
///    Scenes use [_Panel] — a solid fill and a hairline — which looks the same
///    at these sizes and costs nothing.
///  * **Scene bodies are never rebuilt by the swipe.** They rebuild only when
///    [active] flips, which happens once per page settle. The swipe drives
///    transforms in the shell, not widgets here.
///  * **One controller per scene, stopped when the scene is not active**, so
///    three animations never run at once for two pages nobody is looking at.
///  * **Staggered entrances come from one controller with interval curves**,
///    not from N controllers or N delayed timers.
library;

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';

import '../../core/palette.dart';

/// How long a scene's entrance takes end to end, including stagger.
const _entrance = Duration(milliseconds: 900);

/// A slow breath for idle details. Long on purpose: at this speed the eye reads
/// it as "alive", where anything under ~2s reads as "loading".
const _idlePeriod = Duration(milliseconds: 4200);

/// How many breaths before a scene goes still.
///
/// Bounded rather than `repeat()` for two reasons: an endless animation keeps
/// the raster thread working for as long as the app is open, and it makes
/// `pumpAndSettle` in any widget test wait forever. Three breaths is about
/// twelve seconds — long past when a reader has noticed the detail.
const _idleBreaths = 3;

/// Slides content up into place while fading it in.
///
/// `Interval` gives each element its own slice of the single parent animation,
/// which is what makes a stagger cheap — one ticker for a whole scene.
class _Rise extends StatelessWidget {
  final Animation<double> parent;
  final double begin;
  final double end;
  final Widget child;

  const _Rise({
    required this.parent,
    required this.begin,
    required this.end,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final curved = CurvedAnimation(
      parent: parent,
      curve: Interval(begin, end, curve: Curves.easeOutCubic),
    );
    // FadeTransition and SlideTransition, not Opacity and Transform: these
    // drive the layer directly from the animation instead of rebuilding the
    // subtree on every tick.
    return FadeTransition(
      opacity: curved,
      child: SlideTransition(
        // 0.18 of the child's own height: enough to read as a lift, small
        // enough that it never looks like the layout is settling.
        position: Tween<Offset>(
          begin: const Offset(0, 0.18),
          end: Offset.zero,
        ).animate(curved),
        child: child,
      ),
    );
  }
}

/// A scene surface: solid fill, hairline border, generous radius.
///
/// Deliberately not `GlassCard` — see the library note on blur.
class _Panel extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;

  const _Panel({
    required this.child,
    this.padding = const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
  });

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Palette.badgeFill(context),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Palette.hairline(context), width: 1),
      ),
      child: Padding(padding: padding, child: child),
    );
  }
}

/// Headline and one explanatory line, shared by every scene.
class _Copy extends StatelessWidget {
  final Animation<double> parent;
  final String headline;
  final String body;

  const _Copy({
    required this.parent,
    required this.headline,
    required this.body,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Rise(
          parent: parent,
          begin: 0.0,
          end: 0.55,
          child: Text(
            headline,
            maxLines: 3,
            style: TextStyle(
              fontSize: 30,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.9,
              height: 1.08,
              color: Palette.label(context),
            ),
          ),
        ),
        const SizedBox(height: 10),
        _Rise(
          parent: parent,
          begin: 0.12,
          end: 0.7,
          child: Text(
            body,
            maxLines: 4,
            style: TextStyle(
              fontSize: 16,
              height: 1.42,
              letterSpacing: -0.2,
              color: Palette.secondaryLabel(context),
            ),
          ),
        ),
      ],
    );
  }
}

/// Base for the three scenes: owns one controller, runs it when [active].
abstract class _SceneState<T extends StatefulWidget> extends State<T>
    // Two controllers per scene — the entrance and the idle breath — so this
    // needs the plural mixin. SingleTickerProviderStateMixin asserts on the
    // second one.
    with TickerProviderStateMixin {
  late final AnimationController controller = AnimationController(
    duration: _entrance,
    vsync: this,
  );

  /// The slow idle loop. Kept separate so it can be stopped while the entrance
  /// plays and while the scene is offscreen.
  late final AnimationController idle = AnimationController(
    duration: _idlePeriod,
    vsync: this,
  );

  bool get active;
  bool get reduced => MediaQuery.disableAnimationsOf(context);

  /// Fired once, at the beat the scene's own visual resolves. Null for scenes
  /// that do not earn one — a haptic on every page would mean nothing.
  void onResolve() {}

  bool _resolved = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(T oldWidget) {
    super.didUpdateWidget(oldWidget);
    _sync();
  }

  void _sync() {
    if (!active) {
      // Rewind rather than pause: coming back to a scene should replay it, and
      // a stopped controller costs nothing while two other pages are alive.
      controller.value = 0;
      idle.stop();
      _resolved = false;
      return;
    }
    if (reduced) {
      // Reduced motion gets the finished composition immediately, and no loop.
      controller.value = 1;
      idle.value = 0;
      _fire();
      return;
    }
    if (controller.status == AnimationStatus.dismissed) {
      controller.forward().then((_) {
        if (mounted && active) _breathe();
      });
      // The resolve beat lands with the scene's own visual, not at the end of
      // the copy stagger.
      Future<void>.delayed(const Duration(milliseconds: 620), () {
        if (mounted && active) _fire();
      });
    }
  }

  /// Runs the idle a bounded number of times, then rests.
  ///
  /// `orCancel` and the catch matter: stopping the controller (the user swiped
  /// away mid-breath) completes these futures with an error rather than a
  /// value, and an unhandled one would surface as a test failure far from here.
  Future<void> _breathe() async {
    try {
      for (var i = 0; i < _idleBreaths; i++) {
        if (!mounted || !active) return;
        await idle.forward().orCancel;
        if (!mounted || !active) return;
        await idle.reverse().orCancel;
      }
    } on TickerCanceled {
      // Swiped away. Nothing to clean up: _sync already stopped the controller.
    }
  }

  void _fire() {
    if (_resolved) return;
    _resolved = true;
    onResolve();
  }

  @override
  void dispose() {
    controller.dispose();
    idle.dispose();
    super.dispose();
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Scene 1 — the reveal
// ─────────────────────────────────────────────────────────────────────────────

/// Noise resolving into order: a stack of grey bars (mail) collapses and three
/// real insights rise out of it.
///
/// This is the scene that has to earn the app. Everything else in the first run
/// is explanation; this is the thesis, animated.
class InboxScene extends StatefulWidget {
  final bool active;

  const InboxScene({super.key, required this.active});

  @override
  State<InboxScene> createState() => _InboxSceneState();
}

class _InboxSceneState extends _SceneState<InboxScene> {
  @override
  bool get active => widget.active;

  /// The one deliberate haptic in the flow: the moment the noise sorts itself
  /// into three things you can act on. Medium, because it is the point of the
  /// app.
  @override
  void onResolve() => HapticFeedback.mediumImpact();

  @override
  Widget build(BuildContext context) {
    // At accessibility text sizes the choreography cannot fit — absolute slots
    // and two-line rows stop agreeing. Those users get the finished composition
    // as an ordinary Column: the content is the promise, the animation is the
    // flourish, and only one of those is negotiable.
    final crowded = MediaQuery.textScalerOf(context).scale(15) > 21;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _Rise(
          parent: controller,
          begin: 0.0,
          end: 0.4,
          child: Row(
            children: [
              Icon(CupertinoIcons.sun_max_fill,
                  size: 17, color: Palette.label(context)),
              const SizedBox(width: 8),
              Text(
                'NoMail',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.4,
                  color: Palette.label(context),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        _Copy(
          parent: controller,
          headline: 'Your inbox,\nminus the inbox',
          body: 'Six emails arrive. Three of them need you. NoMail keeps '
              'those, each with the link that finishes it.',
        ),
        SizedBox(height: crowded ? 20 : 26),
        if (crowded)
          for (final mail in _mail)
            if (mail.insight != null) ...[
              _Rise(
                parent: controller,
                begin: 0.4,
                end: 0.95,
                child: _InsightRow(mail: mail),
              ),
              const SizedBox(height: 10),
            ]
        else
          // Fixed height so the sort happens inside a stable box: rows are
          // absolutely positioned and move by translation, so the Column never
          // reflows and no layout pass runs per frame.
          SizedBox(
            height: _boxHeight,
            child: AnimatedBuilder(
              animation: controller,
              builder: (context, _) => _SortingInbox(t: controller.value),
            ),
          ),
      ],
    );
  }
}

/// One email in the demonstration, and what NoMail makes of it.
///
/// [insight] null means the mail is noise — it arrives, and it is dropped. Half
/// the point of the scene is watching that happen: "minus the inbox" is a claim
/// about what NoMail *discards*, and a demonstration that only ever added
/// things would not be making it.
typedef _Mail = ({
  String subject,
  IconData? icon,
  ({String title, String detail, String value})? insight,
});

/// Real-shaped mail: an Indian electricity bill, a dispatch notice, a renewal
/// receipt — and the three kinds of thing that make up most of an inbox. Kept
/// and dropped are interleaved so the sort reads as sorting rather than as
/// taking the top three.
const _mail = <_Mail>[
  (
    subject: 'Your BESCOM bill for August is ready',
    icon: CupertinoIcons.doc_text_fill,
    insight: (title: 'BESCOM', detail: 'Due Tuesday', value: '₹1,840'),
  ),
  (subject: 'FLAT 60% OFF — sale ends tonight', icon: null, insight: null),
  (
    subject: 'Your order has been dispatched',
    icon: CupertinoIcons.cube_box_fill,
    insight: (title: 'Amazon', detail: 'Arrives today', value: 'Track'),
  ),
  (subject: 'Weekly digest: 12 stories for you', icon: null, insight: null),
  (
    subject: 'Netflix — your plan renews 12 August',
    icon: CupertinoIcons.arrow_2_circlepath,
    insight: (title: 'Netflix', detail: 'Renews in 6 days', value: '₹699'),
  ),
  (subject: 'Re: Re: Fwd: catch up next week?', icon: null, insight: null),
];

const _boxHeight = 210.0;
const _mailPitch = 25.0;
const _insightHeight = 58.0;
const _insightGap = 9.0;

/// The mail list, then the same rows sorted into insights.
///
/// A `Stack` of positioned rows rather than an animated `Column`: each row keeps
/// its own slot and moves by translation, so nothing relayouts while the scene
/// plays. Dropped mail drifts right and fades; kept mail slides into an insight
/// panel. Two directions, so the sorting is legible as sorting.
class _SortingInbox extends StatelessWidget {
  final double t;

  const _SortingInbox({required this.t});

  @override
  Widget build(BuildContext context) {
    final mailBlock = _mail.length * _mailPitch;
    final mailTop = (_boxHeight - mailBlock) / 2;

    final keptCount = [for (final m in _mail) if (m.insight != null) m].length;
    final insightBlock =
        keptCount * _insightHeight + (keptCount - 1) * _insightGap;
    final insightTop = (_boxHeight - insightBlock) / 2;

    var keptIndex = 0;

    return Stack(
      clipBehavior: Clip.none,
      children: [
        for (var i = 0; i < _mail.length; i++)
          _SortedRow(
            t: t,
            mail: _mail[i],
            // Arrival cascades top to bottom and finishes before the sort
            // starts, so the user reads the inbox before it changes.
            arriveFrom: i * 0.055,
            fromTop: mailTop + i * _mailPitch,
            toTop: _mail[i].insight == null
                ? mailTop + i * _mailPitch
                : insightTop + (keptIndex++) * (_insightHeight + _insightGap),
          ),
      ],
    );
  }
}

class _SortedRow extends StatelessWidget {
  final double t;
  final _Mail mail;
  final double arriveFrom;
  final double fromTop;
  final double toTop;

  const _SortedRow({
    required this.t,
    required this.mail,
    required this.arriveFrom,
    required this.fromTop,
    required this.toTop,
  });

  @override
  Widget build(BuildContext context) {
    // Arrive (staggered, each row over 0.34 of the timeline), then sort from
    // 0.50 once every line has landed.
    final arrive = Curves.easeOutCubic
        .transform(_slice(t, arriveFrom, arriveFrom + 0.34));
    final sort = Curves.easeInOutCubic.transform(_slice(t, 0.5, 1.0));
    final dropped = mail.insight == null;

    final top = fromTop + (toTop - fromTop) * sort;
    // Dropped mail leaves to the right — the direction it arrived from, so it
    // reads as handed back rather than deleted. NoMail never deletes mail, and
    // the animation should not imply otherwise.
    final dx = (1 - arrive) * 34 + (dropped ? sort * 46 : 0);
    final opacity =
        dropped ? (arrive * (1 - sort)).clamp(0.0, 1.0) : arrive.clamp(0.0, 1.0);

    if (opacity <= 0.01) return const SizedBox.shrink();

    return Positioned(
      top: top,
      left: 0,
      right: 0,
      child: Opacity(
        opacity: opacity,
        child: Transform.translate(
          offset: Offset(dx, 0),
          child: dropped
              ? _MailLine(subject: mail.subject)
              // Cross-fade in place: the same row is the mail line and then the
              // insight. That is the claim — nothing new appeared, the mail was
              // understood.
              : Stack(
                  alignment: Alignment.centerLeft,
                  children: [
                    Opacity(
                      opacity: (1 - sort * 1.7).clamp(0.0, 1.0),
                      child: _MailLine(subject: mail.subject),
                    ),
                    Opacity(
                      opacity: _slice(sort, 0.3, 1.0),
                      child: _InsightRow(mail: mail),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}

/// A line in a mail list: an envelope glyph and a subject, nothing else.
class _MailLine extends StatelessWidget {
  final String subject;

  const _MailLine({required this.subject});

  @override
  Widget build(BuildContext context) {
    final muted = Palette.tertiaryLabel(context);
    return SizedBox(
      height: _mailPitch,
      child: Row(
        children: [
          Icon(CupertinoIcons.envelope, size: 13, color: muted),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              subject,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 13.5, color: muted),
            ),
          ),
        ],
      ),
    );
  }
}

/// What the mail became: an icon, a name, when it matters, and its value.
///
/// Deliberately the same silhouette as a real row on the Today tab, so the first
/// screen after onboarding is a shape the user already recognises.
class _InsightRow extends StatelessWidget {
  final _Mail mail;

  const _InsightRow({required this.mail});

  @override
  Widget build(BuildContext context) {
    final insight = mail.insight!;
    final ink = Palette.label(context);
    final muted = Palette.secondaryLabel(context);
    // Beyond about double size, a currency figure will not share a 375pt row
    // with a two-line title — the value moves under the detail instead. Reflow
    // rather than clamp: shrinking the text to make the design fit is the one
    // thing an accessibility size must never be answered with.
    final stacked = MediaQuery.textScalerOf(context).scale(15) > 26;

    final value = Text(
      insight.value,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        fontSize: 15,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.3,
        color: ink,
        fontFeatures: const [FontFeature.tabularFigures()],
      ),
    );

    return _Panel(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      child: Row(
        children: [
          Icon(mail.icon, size: 18, color: ink),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  insight.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    letterSpacing: -0.3,
                    color: ink,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  insight.detail,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 13, color: muted),
                ),
                if (stacked) ...[
                  const SizedBox(height: 3),
                  value,
                ],
              ],
            ),
          ),
          if (!stacked) ...[
            const SizedBox(width: 10),
            // Flexible, not a bare child: a non-flex trailing child claims its
            // full intrinsic width first, which is exactly how GlassRow used to
            // overflow every screen in the app.
            Flexible(child: value),
          ],
        ],
      ),
    );
  }
}

/// Maps [value] onto the sub-range [from]..[to], clamped to 0..1.
double _slice(double value, double from, double to) {
  if (to <= from) return value >= to ? 1 : 0;
  return ((value - from) / (to - from)).clamp(0.0, 1.0);
}

// ─────────────────────────────────────────────────────────────────────────────
// Scene 2 — money that moves quietly
// ─────────────────────────────────────────────────────────────────────────────

/// The price-hike detector, demonstrated: an amount ticks from ₹649 to ₹699
/// while an arrow lifts, and the caption says how it was known.
class PriceScene extends StatefulWidget {
  final bool active;

  const PriceScene({super.key, required this.active});

  @override
  State<PriceScene> createState() => _PriceSceneState();
}

class _PriceSceneState extends _SceneState<PriceScene> {
  @override
  bool get active => widget.active;

  /// Light, not medium: this is a number landing, not the thesis.
  @override
  void onResolve() => HapticFeedback.lightImpact();

  @override
  Widget build(BuildContext context) {
    final ink = Palette.label(context);
    final muted = Palette.secondaryLabel(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _Copy(
          parent: controller,
          headline: 'Money moves\nquietly',
          body: 'Every subscription in one number — and the price rises '
              'nobody announces.',
        ),
        const SizedBox(height: 26),
        // The whole recurring bill, then the list. Leading with the total is
        // what makes the scene about the user's spend rather than about one
        // merchant: a single row would read as "we found a thing", where a
        // total plus a list reads as "we are watching all of it".
        _Rise(
          parent: controller,
          begin: 0.26,
          end: 0.8,
          child: _Panel(
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    // Counts up on entrance. Driven by the scene's own
                    // controller, so the whole panel still costs one ticker.
                    AnimatedBuilder(
                      animation: controller,
                      builder: (context, _) {
                        final t = Curves.easeOutCubic
                            .transform(_slice(controller.value, 0.3, 0.9));
                        return Text(
                          '₹${(_monthlyTotal * t).round()}',
                          style: TextStyle(
                            fontSize: 32,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -1,
                            color: ink,
                            fontFeatures: const [
                              FontFeature.tabularFigures(),
                            ],
                          ),
                        );
                      },
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'a month',
                      style: TextStyle(fontSize: 15, color: muted),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  'across 6 subscriptions',
                  style: TextStyle(fontSize: 13, color: muted),
                ),
                const SizedBox(height: 12),
                for (var i = 0; i < _services.length; i++)
                  _ServiceRow(
                    parent: controller,
                    idle: idle,
                    service: _services[i],
                    // Each row gets its own slice, so the list fills in rather
                    // than appearing all at once.
                    begin: 0.42 + i * 0.09,
                    end: 0.88 + i * 0.04,
                    showDivider: i < _services.length - 1,
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 14),
        _Rise(
          parent: controller,
          begin: 0.62,
          end: 1.0,
          child: Text(
            'Nudges land two days before a renewal, and the day before a '
            'return window shuts.',
            style: TextStyle(fontSize: 14, height: 1.42, color: muted),
          ),
        ),
      ],
    );
  }
}

/// One subscription, and whether its price moved.
///
/// `rose` is what earns the arrow and the delta caption. Exactly one row in the
/// list has it: the contrast is what makes the catch legible — if every row
/// were rising, none of them would stand out.
typedef _Service = ({String name, int amount, int? was});

const _services = <_Service>[
  (name: 'Netflix', amount: 699, was: 649),
  (name: 'Spotify', amount: 119, was: null),
  (name: 'iCloud+', amount: 219, was: null),
];

/// Illustrative, and rounded to look like a real Indian recurring bill rather
/// than the sum of three demo rows — the panel says "6 subscriptions", so the
/// total has to be bigger than what is listed or the arithmetic invites doubt.
const _monthlyTotal = 1737;

class _ServiceRow extends StatelessWidget {
  final Animation<double> parent;
  final Animation<double> idle;
  final _Service service;
  final double begin;
  final double end;
  final bool showDivider;

  const _ServiceRow({
    required this.parent,
    required this.idle,
    required this.service,
    required this.begin,
    required this.end,
    required this.showDivider,
  });

  @override
  Widget build(BuildContext context) {
    final ink = Palette.label(context);
    final muted = Palette.secondaryLabel(context);
    final was = service.was;
    final rose = was != null;

    return _Rise(
      parent: parent,
      begin: begin,
      end: end,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 9),
        child: Column(
          children: [
            Row(
              children: [
                if (rose)
                  // The arrow is the idle detail: it lifts about two points on
                  // a 4.2s breath, which reads as attention rather than motion.
                  AnimatedBuilder(
                    animation: idle,
                    builder: (context, child) => Transform.translate(
                      offset: Offset(0, -2 * idle.value),
                      child: child,
                    ),
                    child: Icon(CupertinoIcons.arrow_up_right,
                        size: 15, color: ink),
                  )
                else
                  Icon(CupertinoIcons.arrow_2_circlepath,
                      size: 15, color: muted),
                const SizedBox(width: 9),
                Expanded(
                  child: Text(
                    service.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 16,
                      letterSpacing: -0.3,
                      color: ink,
                    ),
                  ),
                ),
                if (rose) ...[
                  Text(
                    '₹$was',
                    style: TextStyle(
                      fontSize: 14,
                      color: muted,
                      decoration: TextDecoration.lineThrough,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                  const SizedBox(width: 7),
                ],
                Text(
                  '₹${service.amount}',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: rose ? FontWeight.w700 : FontWeight.w500,
                    letterSpacing: -0.3,
                    color: rose ? ink : muted,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
            if (rose) ...[
              const SizedBox(height: 5),
              Align(
                alignment: Alignment.centerLeft,
                child: Padding(
                  padding: const EdgeInsets.only(left: 24),
                  child: Text(
                    'Up ₹${service.amount - was} since last month',
                    style: TextStyle(fontSize: 12.5, color: muted),
                  ),
                ),
              ),
            ],
            if (showDivider) ...[
              const SizedBox(height: 9),
              Container(height: 1, color: Palette.hairline(context)),
            ],
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Scene 3 — one tap, the right place
// ─────────────────────────────────────────────────────────────────────────────

/// The destination promise: every action says where it lands before you tap it.
///
/// Chosen as the closing scene because it is the app's most unusual courtesy
/// and the easiest to show in three rows.
class DestinationScene extends StatefulWidget {
  final bool active;

  const DestinationScene({super.key, required this.active});

  @override
  State<DestinationScene> createState() => _DestinationSceneState();
}

class _DestinationSceneState extends _SceneState<DestinationScene> {
  @override
  bool get active => widget.active;

  static const _rows = [
    (
      icon: CupertinoIcons.cube_box_fill,
      action: 'Track package',
      mark: CupertinoIcons.app_badge,
      where: 'Delhivery',
    ),
    (
      icon: CupertinoIcons.doc_text_fill,
      action: 'Pay bill',
      mark: CupertinoIcons.arrow_up_right_square,
      where: 'your UPI app',
    ),
    (
      icon: CupertinoIcons.arrow_2_circlepath,
      action: 'Manage plan',
      mark: CupertinoIcons.globe,
      where: 'in NoMail',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final ink = Palette.label(context);
    final muted = Palette.secondaryLabel(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _Copy(
          parent: controller,
          headline: 'One tap,\nthe right place',
          body: 'Every action opens the app you actually have — and says '
              'which one before you touch it.',
        ),
        const SizedBox(height: 26),
        for (var i = 0; i < _rows.length; i++) ...[
          if (i > 0) const SizedBox(height: 10),
          _Rise(
            parent: controller,
            begin: 0.28 + i * 0.12,
            end: 0.82 + i * 0.06,
            child: _Panel(
              child: Row(
                children: [
                  Icon(_rows[i].icon, size: 18, color: ink),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      _rows[i].action,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 16,
                        letterSpacing: -0.3,
                        color: ink,
                      ),
                    ),
                  ),
                  Icon(_rows[i].mark, size: 13, color: muted),
                  const SizedBox(width: 5),
                  Flexible(
                    child: Text(
                      _rows[i].where,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.end,
                      style: TextStyle(fontSize: 13, color: muted),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
        const SizedBox(height: 18),
        _Rise(
          parent: controller,
          begin: 0.62,
          end: 1.0,
          child: Row(
            children: [
              Icon(CupertinoIcons.lock_shield_fill, size: 15, color: muted),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  'Read-only. Stored on this device. '
                  'NoMail cannot send, move or delete mail.',
                  style: TextStyle(fontSize: 13, height: 1.4, color: muted),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Six ambient dots that drift behind the scenes, seeded per page so no two
/// pages look identical.
///
/// A `CustomPaint` again, and driven by the swipe offset the shell already
/// has — so the backdrop parallaxes for free rather than owning a ticker.
class SceneBackdrop extends StatelessWidget {
  final double phase;
  final int seed;

  const SceneBackdrop({super.key, required this.phase, required this.seed});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _BackdropPainter(
        phase: phase,
        seed: seed,
        tint: Palette.accent(context),
      ),
      size: Size.infinite,
    );
  }
}

class _BackdropPainter extends CustomPainter {
  final double phase;
  final int seed;
  final Color tint;

  _BackdropPainter({
    required this.phase,
    required this.seed,
    required this.tint,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final random = math.Random(seed);
    for (var i = 0; i < 6; i++) {
      final x = random.nextDouble();
      final y = random.nextDouble();
      final r = 40 + random.nextDouble() * 90;
      // Depth: further dots move less, which is what makes it read as parallax
      // rather than as a sliding image.
      final depth = 0.25 + random.nextDouble() * 0.75;
      final centre = Offset(
        x * size.width - phase * 60 * depth,
        y * size.height,
      );
      canvas.drawCircle(
        centre,
        r,
        Paint()
          ..shader = ui.Gradient.radial(centre, r, [
            tint.withValues(alpha: 0.05 * depth),
            tint.withValues(alpha: 0),
          ]),
      );
    }
  }

  @override
  bool shouldRepaint(_BackdropPainter old) =>
      old.phase != phase || old.tint != tint;
}
