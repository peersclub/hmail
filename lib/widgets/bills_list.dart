import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/enhanced_email_provider.dart';
import 'package:intl/intl.dart';

class BillsList extends StatelessWidget {
  const BillsList({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<EnhancedEmailProvider>(
      builder: (context, provider, _) {
        if (provider.bills.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.receipt_long_outlined,
                  size: 64,
                  color: Colors.grey,
                ),
                const SizedBox(height: 16),
                Text(
                  'No bills found',
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

        final unpaidBills = provider.bills.where((b) => !b.isPaid).toList();
        final paidBills = provider.bills.where((b) => b.isPaid).toList();

        return RefreshIndicator(
          onRefresh: () => provider.fetchAndAnalyzeEmails(),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (unpaidBills.isNotEmpty) ...[
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.red.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.red.withOpacity(0.3)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.warning, color: Colors.red),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${unpaidBills.length} Unpaid Bills',
                              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Text(
                              'Total: \$${provider.totalUnpaidBills.toStringAsFixed(2)}',
                              style: Theme.of(context).textTheme.bodyMedium,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Unpaid Bills',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 8),
                ...unpaidBills.map((bill) => _buildBillCard(context, bill)),
                const SizedBox(height: 24),
              ],
              if (paidBills.isNotEmpty) ...[
                Text(
                  'Paid Bills',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 8),
                ...paidBills.map((bill) => _buildBillCard(context, bill)),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _buildBillCard(BuildContext context, bill) {
    final isOverdue = !bill.isPaid && bill.dueDate.isBefore(DateTime.now());
    
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      color: isOverdue ? Colors.red.withOpacity(0.05) : null,
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: bill.isPaid ? Colors.green : (isOverdue ? Colors.red : Colors.orange),
          child: Icon(
            bill.isPaid ? Icons.check : Icons.schedule,
            color: Colors.white,
          ),
        ),
        title: Text(bill.provider),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(bill.category),
            Text(
              'Due: ${DateFormat('MMM dd, yyyy').format(bill.dueDate)}',
              style: TextStyle(
                color: isOverdue ? Colors.red : null,
                fontWeight: isOverdue ? FontWeight.bold : null,
              ),
            ),
            if (bill.accountNumber != null)
              Text(
                'Account: ${bill.accountNumber}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
          ],
        ),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              '\$${bill.amount.toStringAsFixed(2)}',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
                color: bill.isPaid ? Colors.green : null,
              ),
            ),
            if (bill.isPaid)
              const Text(
                'PAID',
                style: TextStyle(
                  color: Colors.green,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              )
            else if (isOverdue)
              const Text(
                'OVERDUE',
                style: TextStyle(
                  color: Colors.red,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
          ],
        ),
      ),
    );
  }
}