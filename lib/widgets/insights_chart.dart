import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:provider/provider.dart';
import '../providers/email_provider.dart';

class InsightsChart extends StatelessWidget {
  const InsightsChart({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<EmailProvider>(
      builder: (context, provider, _) {
        final data = [
          PieChartSectionData(
            value: provider.totalMonthlySpend,
            title: 'Subscriptions',
            color: Colors.blue,
            radius: 50,
            titleStyle: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          PieChartSectionData(
            value: provider.totalUnpaidBills,
            title: 'Bills',
            color: Colors.red,
            radius: 50,
            titleStyle: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          if (provider.amazonOrders.isNotEmpty)
            PieChartSectionData(
              value: provider.amazonOrders
                  .fold<double>(0.0, (sum, order) => sum + order.amount),
              title: 'Shopping',
              color: Colors.orange,
              radius: 50,
              titleStyle: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
        ];

        if (data.every((d) => d.value == 0)) {
          return const Center(
            child: Text('No spending data available'),
          );
        }

        return PieChart(
          PieChartData(
            sections: data,
            centerSpaceRadius: 40,
            sectionsSpace: 2,
            borderData: FlBorderData(show: false),
          ),
        );
      },
    );
  }
}