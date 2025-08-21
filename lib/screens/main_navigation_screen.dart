import 'package:flutter/material.dart';
import 'inbox_screen.dart';
import 'home_screen.dart';
import '../widgets/amazon_orders_list.dart';
import '../widgets/subscriptions_list.dart';
import '../widgets/bills_list.dart';

class MainNavigationScreen extends StatefulWidget {
  const MainNavigationScreen({super.key});

  @override
  State<MainNavigationScreen> createState() => _MainNavigationScreenState();
}

class _MainNavigationScreenState extends State<MainNavigationScreen> {
  int _selectedIndex = 0;

  final List<Widget> _screens = [
    const InboxScreen(),
    const HomeScreen(),
    const AmazonOrdersList(),
    const SubscriptionsList(),
    const BillsList(),
  ];

  final List<NavigationDestination> _destinations = const [
    NavigationDestination(
      icon: Icon(Icons.inbox),
      selectedIcon: Icon(Icons.inbox),
      label: 'Inbox',
    ),
    NavigationDestination(
      icon: Icon(Icons.insights_outlined),
      selectedIcon: Icon(Icons.insights),
      label: 'Insights',
    ),
    NavigationDestination(
      icon: Icon(Icons.shopping_cart_outlined),
      selectedIcon: Icon(Icons.shopping_cart),
      label: 'Orders',
    ),
    NavigationDestination(
      icon: Icon(Icons.subscriptions_outlined),
      selectedIcon: Icon(Icons.subscriptions),
      label: 'Subscriptions',
    ),
    NavigationDestination(
      icon: Icon(Icons.receipt_long_outlined),
      selectedIcon: Icon(Icons.receipt_long),
      label: 'Bills',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _selectedIndex,
        children: _screens,
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: (index) {
          setState(() {
            _selectedIndex = index;
          });
        },
        destinations: _destinations,
      ),
    );
  }
}