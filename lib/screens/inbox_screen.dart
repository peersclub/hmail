import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/enhanced_email_provider.dart';
import '../models/email.dart';
import '../widgets/email_list_item.dart';
import '../widgets/email_filter_chips.dart';
import 'email_detail_screen.dart';
import 'compose_email_screen.dart';
import 'package:intl/intl.dart';

class InboxScreen extends StatefulWidget {
  const InboxScreen({super.key});

  @override
  State<InboxScreen> createState() => _InboxScreenState();
}

class _InboxScreenState extends State<InboxScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final TextEditingController _searchController = TextEditingController();
  EmailCategory? _selectedCategory;
  bool _showFilters = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 7, vsync: this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<EnhancedEmailProvider>().fetchEmails();
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('NoMail'),
        elevation: 0,
        bottom: PreferredSize(
          preferredSize: Size.fromHeight(_showFilters ? 120 : 60),
          child: Column(
            children: [
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surface,
                  borderRadius: BorderRadius.circular(30),
                  border: Border.all(
                    color: Theme.of(context).colorScheme.outline.withOpacity(0.2),
                  ),
                ),
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.menu),
                      onPressed: () => Scaffold.of(context).openDrawer(),
                    ),
                    Expanded(
                      child: TextField(
                        controller: _searchController,
                        decoration: InputDecoration(
                          hintText: 'Search emails with AI...',
                          border: InputBorder.none,
                          suffixIcon: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: Icon(_showFilters ? Icons.filter_alt : Icons.filter_alt_outlined),
                                onPressed: () {
                                  setState(() {
                                    _showFilters = !_showFilters;
                                  });
                                },
                              ),
                              IconButton(
                                icon: const Icon(Icons.search),
                                onPressed: _performSearch,
                              ),
                            ],
                          ),
                        ),
                        onSubmitted: (_) => _performSearch(),
                      ),
                    ),
                  ],
                ),
              ),
              if (_showFilters)
                Container(
                  height: 50,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: EmailFilterChips(
                    onFilterChanged: (filter) {
                      context.read<EnhancedEmailProvider>().applyFilter(filter);
                    },
                  ),
                ),
            ],
          ),
        ),
      ),
      drawer: _buildDrawer(),
      body: Column(
        children: [
          TabBar(
            controller: _tabController,
            isScrollable: true,
            tabs: const [
              Tab(text: 'All', icon: Icon(Icons.inbox, size: 18)),
              Tab(text: 'Primary', icon: Icon(Icons.person, size: 18)),
              Tab(text: 'Social', icon: Icon(Icons.people, size: 18)),
              Tab(text: 'Promotions', icon: Icon(Icons.local_offer, size: 18)),
              Tab(text: 'Updates', icon: Icon(Icons.info, size: 18)),
              Tab(text: 'Finance', icon: Icon(Icons.attach_money, size: 18)),
              Tab(text: 'Work', icon: Icon(Icons.work, size: 18)),
            ],
            onTap: (index) {
              EmailCategory? category;
              switch (index) {
                case 1:
                  category = EmailCategory.primary;
                  break;
                case 2:
                  category = EmailCategory.social;
                  break;
                case 3:
                  category = EmailCategory.promotions;
                  break;
                case 4:
                  category = EmailCategory.updates;
                  break;
                case 5:
                  category = EmailCategory.finance;
                  break;
                case 6:
                  category = EmailCategory.work;
                  break;
              }
              context.read<EnhancedEmailProvider>().filterByCategory(category);
            },
          ),
          Expanded(
            child: Consumer<EnhancedEmailProvider>(
              builder: (context, provider, _) {
                if (provider.isLoading && provider.emails.isEmpty) {
                  return const Center(child: CircularProgressIndicator());
                }

                if (provider.emails.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.inbox,
                          size: 64,
                          color: Colors.grey,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'No emails found',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        const SizedBox(height: 8),
                        ElevatedButton.icon(
                          onPressed: () => provider.fetchEmails(),
                          icon: const Icon(Icons.refresh),
                          label: const Text('Refresh'),
                        ),
                      ],
                    ),
                  );
                }

                return RefreshIndicator(
                  onRefresh: () => provider.fetchEmails(),
                  child: ListView.builder(
                    itemCount: provider.emails.length,
                    itemBuilder: (context, index) {
                      final email = provider.emails[index];
                      return EmailListItem(
                        email: email,
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => EmailDetailScreen(email: email),
                            ),
                          );
                        },
                        onSwipeLeft: () => provider.archiveEmail(email.id),
                        onSwipeRight: () => provider.deleteEmail(email.id),
                        onStarToggle: () => provider.toggleStar(email.id, !email.isStarred),
                      );
                    },
                  ),
                );
              },
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const ComposeEmailScreen()),
          );
        },
        icon: const Icon(Icons.edit),
        label: const Text('Compose'),
      ),
    );
  }

  Widget _buildDrawer() {
    return Drawer(
      child: Consumer<EnhancedEmailProvider>(
        builder: (context, provider, _) {
          return ListView(
            children: [
              UserAccountsDrawerHeader(
                accountName: Text(provider.userName ?? 'User'),
                accountEmail: Text(provider.userEmail ?? ''),
                currentAccountPicture: provider.userPhoto != null
                    ? CircleAvatar(backgroundImage: NetworkImage(provider.userPhoto!))
                    : const CircleAvatar(child: Icon(Icons.person)),
              ),
              ListTile(
                leading: const Icon(Icons.inbox),
                title: const Text('Inbox'),
                trailing: provider.unreadCount > 0
                    ? CircleAvatar(
                        radius: 12,
                        backgroundColor: Colors.red,
                        child: Text(
                          provider.unreadCount.toString(),
                          style: const TextStyle(fontSize: 12, color: Colors.white),
                        ),
                      )
                    : null,
                onTap: () {
                  Navigator.pop(context);
                  provider.filterByCategory(null);
                },
              ),
              ListTile(
                leading: const Icon(Icons.star),
                title: const Text('Starred'),
                onTap: () {
                  Navigator.pop(context);
                  provider.applyFilter(EmailFilter(isStarred: true));
                },
              ),
              ListTile(
                leading: const Icon(Icons.schedule),
                title: const Text('Snoozed'),
                onTap: () {
                  Navigator.pop(context);
                },
              ),
              ListTile(
                leading: const Icon(Icons.label_important),
                title: const Text('Important'),
                onTap: () {
                  Navigator.pop(context);
                  provider.applyFilter(EmailFilter(isImportant: true));
                },
              ),
              ListTile(
                leading: const Icon(Icons.send),
                title: const Text('Sent'),
                onTap: () {
                  Navigator.pop(context);
                },
              ),
              ListTile(
                leading: const Icon(Icons.drafts),
                title: const Text('Drafts'),
                onTap: () {
                  Navigator.pop(context);
                },
              ),
              const Divider(),
              ListTile(
                leading: const Icon(Icons.label),
                title: const Text('Labels'),
                onTap: () {
                  Navigator.pop(context);
                },
              ),
              const Divider(),
              ListTile(
                leading: const Icon(Icons.settings),
                title: const Text('Settings'),
                onTap: () {
                  Navigator.pop(context);
                },
              ),
              ListTile(
                leading: const Icon(Icons.help),
                title: const Text('Help & Feedback'),
                onTap: () {
                  Navigator.pop(context);
                },
              ),
              ListTile(
                leading: const Icon(Icons.logout),
                title: const Text('Sign Out'),
                onTap: () {
                  Navigator.pop(context);
                  provider.signOut();
                },
              ),
            ],
          );
        },
      ),
    );
  }

  void _performSearch() {
    final query = _searchController.text.trim();
    if (query.isNotEmpty) {
      context.read<EnhancedEmailProvider>().searchEmails(query);
    }
  }
}