import 'package:flutter/cupertino.dart';
import 'package:provider/provider.dart';

import '../../core/palette.dart';
import '../../domain/actions.dart';
import '../../domain/models.dart';
import '../../state/app_controller.dart';
import '../action_sheet.dart';
import '../format.dart';
import '../glass/glass.dart';

class PackagesScreen extends StatelessWidget {
  const PackagesScreen({super.key});

  static String _stageLabel(DeliveryStatus status) => switch (status) {
        DeliveryStatus.ordered => 'Order confirmed',
        DeliveryStatus.shipped => 'Shipped',
        DeliveryStatus.outForDelivery => 'Out for delivery',
        DeliveryStatus.delivered => 'Delivered',
      };

  @override
  Widget build(BuildContext context) {
    final snapshot = context.watch<AppController>().snapshot;

    final active = snapshot.activeDeliveries
      ..sort((a, b) => b.status.index.compareTo(a.status.index));
    final delivered = snapshot.deliveries
        .where((d) => d.status == DeliveryStatus.delivered)
        .toList();

    return ListView(
      physics: const BouncingScrollPhysics(),
      padding: EdgeInsets.zero,
      children: [
        SizedBox(height: MediaQuery.paddingOf(context).top),
        const GlassHeader(eyebrow: 'Deliveries', title: 'Packages'),
        if (active.isEmpty && delivered.isEmpty)
          const GlassEmptyState(
            icon: CupertinoIcons.cube_box,
            title: 'No Deliveries Tracked',
            caption:
                'Order confirmations and shipping updates from your email will appear here.',
          ),
        if (active.isNotEmpty) ...[
          const SectionLabel('On the way'),
          for (final delivery in active)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => showInsightActions(
                  context,
                  title: delivery.merchant,
                  message: _stageLabel(delivery.status),
                  actions: actionsForDelivery(delivery),
                ),
                child: GlassCard(
                  padding: const EdgeInsets.all(18),
                  child: _ActiveDelivery(delivery: delivery),
                ),
              ),
            ),
        ],
        if (delivered.isNotEmpty)
          GlassSection(
            label: 'Delivered',
            children: [
              for (final delivery in delivered)
                GlassRow(
                  icon: CupertinoIcons.checkmark_circle_fill,
                  title: delivery.merchant,
                  subtitle: 'Delivered ${formatDay(delivery.lastSeen)}'
                      '${delivery.carrier != null ? ' · ${delivery.carrier}' : ''}',
                  onTap: () => showInsightActions(
                    context,
                    title: delivery.merchant,
                    actions: actionsForDelivery(delivery),
                  ),
                ),
            ],
          ),
        const SizedBox(height: kDockClearance),
      ],
    );
  }
}

class _ActiveDelivery extends StatelessWidget {
  final Delivery delivery;

  const _ActiveDelivery({required this.delivery});

  @override
  Widget build(BuildContext context) {
    final stageIndex = delivery.status.index;
    final stageLabel = PackagesScreen._stageLabel(delivery.status);
    final subtitle = [
      stageLabel,
      if (delivery.carrier != null) delivery.carrier!,
      if (delivery.trackingNumber != null) delivery.trackingNumber!,
    ].join(' · ');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const IconBadge(CupertinoIcons.cube_box_fill),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    delivery.merchant,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.2,
                      color: Palette.label(context),
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      color: Palette.secondaryLabel(context),
                    ),
                  ),
                ],
              ),
            ),
            if (delivery.eta != null) ...[
              const SizedBox(width: 12),
              Text(
                formatDay(delivery.eta!),
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Palette.urgency(context, delivery.eta),
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            for (var i = 0; i < 4; i++) ...[
              if (i > 0) const SizedBox(width: 5),
              Expanded(
                child: Container(
                  height: 5,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(2.5),
                    color: i <= stageIndex
                        ? Palette.accent(context)
                        : Palette.track(context),
                  ),
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 8),
        Text(
          stageLabel,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: Palette.accent(context),
          ),
        ),
      ],
    );
  }
}
