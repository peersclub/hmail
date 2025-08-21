import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/email_provider.dart';
import 'package:intl/intl.dart';

class SubscriptionsList extends StatelessWidget {
  const SubscriptionsList({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<EmailProvider>(
      builder: (context, provider, _) {
        if (provider.subscriptions.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.subscriptions_outlined,
                  size: 64,
                  color: Colors.grey,
                ),
                const SizedBox(height: 16),
                Text(
                  'No subscriptions found',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 8),
                ElevatedButton.icon(
                  onPressed: () => provider.fetchAndAnalyzeEmails(),
                  icon: const Icon(Icons.refresh),
                  label: const Text('Refresh'),
                ),
              ],
            ),
          );
        }

        final totalMonthly = provider.totalMonthlySpend;
        final totalYearly = provider.projectedYearlySpend;

        return RefreshIndicator(
          onRefresh: () => provider.fetchAndAnalyzeEmails(),
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                color: Theme.of(context).colorScheme.primaryContainer,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    Column(
                      children: [
                        Text(
                          '\$${totalMonthly.toStringAsFixed(2)}',
                          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          'Monthly Total',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                    Column(
                      children: [
                        Text(
                          '\$${totalYearly.toStringAsFixed(0)}',
                          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          'Yearly Projection',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: provider.subscriptions.length,
                  itemBuilder: (context, index) {
                    final subscription = provider.subscriptions[index];
                    return Card(
                      margin: const EdgeInsets.only(bottom: 12),
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: _getServiceColor(subscription.service),
                          child: Text(
                            subscription.service.substring(0, 1).toUpperCase(),
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        title: Text(subscription.service),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              subscription.status,
                              style: TextStyle(
                                color: subscription.status == 'Active'
                                  ? Colors.green
                                  : Colors.orange,
                              ),
                            ),
                            if (subscription.nextBillingDate != null)
                              Text(
                                'Next billing: ${DateFormat('MMM dd').format(subscription.nextBillingDate!)}',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                          ],
                        ),
                        trailing: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              '\$${subscription.monthlyAmount.toStringAsFixed(2)}',
                              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Text(
                              'per month',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Color _getServiceColor(String service) {
    final lower = service.toLowerCase();
    if (lower.contains('netflix')) return Colors.red;
    if (lower.contains('spotify')) return Colors.green;
    if (lower.contains('apple')) return Colors.grey;
    if (lower.contains('google')) return Colors.blue;
    if (lower.contains('microsoft')) return Colors.blue.shade700;
    if (lower.contains('adobe')) return Colors.red.shade700;
    if (lower.contains('amazon')) return Colors.orange;
    return Colors.purple;
  }
}