import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/enhanced_email_provider.dart';
import 'package:intl/intl.dart';

class AmazonOrdersList extends StatelessWidget {
  const AmazonOrdersList({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<EnhancedEmailProvider>(
      builder: (context, provider, _) {
        if (provider.amazonOrders.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.shopping_cart_outlined,
                  size: 64,
                  color: Colors.grey,
                ),
                const SizedBox(height: 16),
                Text(
                  'No Amazon orders found',
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

        return RefreshIndicator(
          onRefresh: () => provider.fetchAndAnalyzeEmails(),
          child: ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: provider.amazonOrders.length,
            itemBuilder: (context, index) {
              final order = provider.amazonOrders[index];
              return Card(
                margin: const EdgeInsets.only(bottom: 12),
                child: ExpansionTile(
                  leading: CircleAvatar(
                    backgroundColor: _getStatusColor(order.status),
                    child: Icon(
                      _getStatusIcon(order.status),
                      color: Colors.white,
                    ),
                  ),
                  title: Text('Order #${order.orderId}'),
                  subtitle: Text(
                    DateFormat('MMM dd, yyyy').format(order.orderDate),
                  ),
                  trailing: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        '\$${order.amount.toStringAsFixed(2)}',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        order.status,
                        style: TextStyle(
                          color: _getStatusColor(order.status),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (order.items.isNotEmpty) ...[
                            Text(
                              'Items:',
                              style: Theme.of(context).textTheme.titleSmall,
                            ),
                            const SizedBox(height: 8),
                            ...order.items.map((item) => Padding(
                              padding: const EdgeInsets.only(left: 16, bottom: 4),
                              child: Row(
                                children: [
                                  const Icon(Icons.circle, size: 6),
                                  const SizedBox(width: 8),
                                  Expanded(child: Text(item)),
                                ],
                              ),
                            )),
                          ],
                          if (order.deliveryDate != null) ...[
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                const Icon(Icons.local_shipping, size: 16),
                                const SizedBox(width: 8),
                                Text(
                                  'Expected: ${DateFormat('MMM dd').format(order.deliveryDate!)}',
                                  style: Theme.of(context).textTheme.bodyMedium,
                                ),
                              ],
                            ),
                          ],
                          if (order.trackingNumber != null) ...[
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                const Icon(Icons.confirmation_number, size: 16),
                                const SizedBox(width: 8),
                                Text(
                                  'Tracking: ${order.trackingNumber}',
                                  style: Theme.of(context).textTheme.bodyMedium,
                                ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        );
      },
    );
  }

  Color _getStatusColor(String status) {
    final lowerStatus = status.toLowerCase();
    if (lowerStatus.contains('delivered')) return Colors.green;
    if (lowerStatus.contains('transit') || lowerStatus.contains('shipped')) {
      return Colors.orange;
    }
    if (lowerStatus.contains('cancelled')) return Colors.red;
    return Colors.blue;
  }

  IconData _getStatusIcon(String status) {
    final lowerStatus = status.toLowerCase();
    if (lowerStatus.contains('delivered')) return Icons.check_circle;
    if (lowerStatus.contains('transit') || lowerStatus.contains('shipped')) {
      return Icons.local_shipping;
    }
    if (lowerStatus.contains('cancelled')) return Icons.cancel;
    return Icons.shopping_cart;
  }
}