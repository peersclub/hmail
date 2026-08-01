import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/enhanced_email_provider.dart';
import '../widgets/dashboard_card.dart';
import '../widgets/amazon_orders_list.dart';
import '../widgets/subscriptions_list.dart';
import '../widgets/bills_list.dart';
import '../widgets/insights_chart.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _selectedIndex = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<EnhancedEmailProvider>().fetchAndAnalyzeEmails();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('NoMail Insights'),
        elevation: 0,
        actions: [
          Consumer<EnhancedEmailProvider>(
            builder: (context, provider, _) {
              if (provider.userPhoto != null) {
                return Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: CircleAvatar(
                    backgroundImage: NetworkImage(provider.userPhoto!),
                  ),
                );
              }
              return const SizedBox();
            },
          ),
          PopupMenuButton(
            itemBuilder: (context) => [
              PopupMenuItem(
                child: ListTile(
                  leading: const Icon(Icons.refresh),
                  title: const Text('Refresh'),
                  onTap: () {
                    Navigator.pop(context);
                    context.read<EnhancedEmailProvider>().fetchAndAnalyzeEmails();
                  },
                ),
              ),
              PopupMenuItem(
                child: ListTile(
                  leading: const Icon(Icons.logout),
                  title: const Text('Sign Out'),
                  onTap: () {
                    Navigator.pop(context);
                    context.read<EnhancedEmailProvider>().signOut();
                  },
                ),
              ),
            ],
          ),
        ],
      ),
      body: Consumer<EnhancedEmailProvider>(
        builder: (context, provider, _) {
          if (provider.isLoading) {
            return const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('Analyzing your emails...'),
                ],
              ),
            );
          }

          return IndexedStack(
            index: _selectedIndex,
            children: [
              _buildDashboard(provider),
              const AmazonOrdersList(),
              const SubscriptionsList(),
              const BillsList(),
            ],
          );
        },
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: (index) {
          setState(() {
            _selectedIndex = index;
          });
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.dashboard),
            label: 'Dashboard',
          ),
          NavigationDestination(
            icon: Icon(Icons.shopping_cart),
            label: 'Orders',
          ),
          NavigationDestination(
            icon: Icon(Icons.subscriptions),
            label: 'Subscriptions',
          ),
          NavigationDestination(
            icon: Icon(Icons.receipt_long),
            label: 'Bills',
          ),
        ],
      ),
    );
  }

  Widget _buildDashboard(EnhancedEmailProvider provider) {
    return RefreshIndicator(
      onRefresh: () => provider.fetchAndAnalyzeEmails(),
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Welcome back, ${provider.userName ?? 'User'}!',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            Text(
              'Here are your email insights',
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                color: Colors.grey,
              ),
            ),
            const SizedBox(height: 24),
            GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 16,
              crossAxisSpacing: 16,
              childAspectRatio: 1.5,
              children: [
                DashboardCard(
                  title: 'Amazon Orders',
                  value: provider.amazonOrders.length.toString(),
                  subtitle: '${provider.ordersInTransit} in transit',
                  icon: Icons.shopping_cart,
                  color: Colors.orange,
                ),
                DashboardCard(
                  title: 'Subscriptions',
                  value: provider.subscriptions.length.toString(),
                  subtitle: '\$${provider.totalMonthlySpend.toStringAsFixed(2)}/mo',
                  icon: Icons.subscriptions,
                  color: Colors.blue,
                ),
                DashboardCard(
                  title: 'Unpaid Bills',
                  value: provider.unpaidBillsCount.toString(),
                  subtitle: '\$${provider.totalUnpaidBills.toStringAsFixed(2)}',
                  icon: Icons.receipt_long,
                  color: Colors.red,
                ),
                DashboardCard(
                  title: 'Yearly Projection',
                  value: '\$${provider.projectedYearlySpend.toStringAsFixed(0)}',
                  subtitle: 'Subscriptions only',
                  icon: Icons.trending_up,
                  color: Colors.green,
                ),
              ],
            ),
            const SizedBox(height: 24),
            if (provider.insights.isNotEmpty) ...[
              Text(
                'Spending Overview',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 16),
              const SizedBox(
                height: 200,
                child: InsightsChart(),
              ),
            ],
            const SizedBox(height: 24),
            Text(
              'Recent Insights',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 16),
            if (provider.insights.isEmpty)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    'No insights available. Pull down to refresh.',
                    style: Theme.of(context).textTheme.bodyLarge,
                  ),
                ),
              )
            else
              ...provider.insights.take(5).map((insight) => Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: _getCategoryColor(insight.category),
                    child: Icon(
                      _getCategoryIcon(insight.category),
                      color: Colors.white,
                    ),
                  ),
                  title: Text(insight.title),
                  subtitle: Text(insight.description),
                  trailing: insight.value != null
                    ? Text(
                        insight.value is num
                          ? '\$${insight.value.toStringAsFixed(2)}'
                          : insight.value.toString(),
                        style: Theme.of(context).textTheme.titleMedium,
                      )
                    : null,
                ),
              )),
          ],
        ),
      ),
    );
  }

  Color _getCategoryColor(String category) {
    switch (category.toLowerCase()) {
      case 'amazon_orders':
      case 'amazon':
        return Colors.orange;
      case 'subscriptions':
      case 'subscription':
        return Colors.blue;
      case 'bills':
      case 'bill':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  IconData _getCategoryIcon(String category) {
    switch (category.toLowerCase()) {
      case 'amazon_orders':
      case 'amazon':
        return Icons.shopping_cart;
      case 'subscriptions':
      case 'subscription':
        return Icons.subscriptions;
      case 'bills':
      case 'bill':
        return Icons.receipt_long;
      default:
        return Icons.info;
    }
  }
}