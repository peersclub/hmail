import 'package:flutter/foundation.dart';
import '../services/enhanced_gmail_service.dart';
import '../services/ai_service.dart';
import '../models/email.dart';
import '../models/email_insight.dart';

class EnhancedEmailProvider extends ChangeNotifier {
  final EnhancedGmailService _gmailService = EnhancedGmailService();
  final AIService _aiService = AIService();

  bool _isLoading = false;
  bool _isSignedIn = false;
  bool _isDemoMode = false;
  String? _userEmail;
  String? _userName;
  String? _userPhoto;

  List<Email> _emails = [];
  List<Email> _filteredEmails = [];
  EmailFilter? _currentFilter;
  Map<String, EmailThread> _threads = {};
  List<String> _labels = [];
  
  List<EmailInsight> _insights = [];
  List<AmazonOrder> _amazonOrders = [];
  List<Subscription> _subscriptions = [];
  List<Bill> _bills = [];

  bool get isLoading => _isLoading;
  bool get isSignedIn => _isSignedIn;
  bool get isDemoMode => _isDemoMode;
  String? get userEmail => _userEmail;
  String? get userName => _userName;
  String? get userPhoto => _userPhoto;
  
  List<Email> get emails => _filteredEmails.isNotEmpty ? _filteredEmails : _emails;
  List<String> get labels => _labels;
  int get unreadCount => emails.where((e) => !e.isRead).length;
  
  List<EmailInsight> get insights => _insights;
  List<AmazonOrder> get amazonOrders => _amazonOrders;
  List<Subscription> get subscriptions => _subscriptions;
  List<Bill> get bills => _bills;

  Future<bool> signIn() async {
    _isLoading = true;
    notifyListeners();

    final signedIn = await _gmailService.signIn();

    if (signedIn) {
      final account = _gmailService.currentUser!;
      _isSignedIn = true;
      _isDemoMode = false;
      _userEmail = account.email;
      _userName = account.displayName ?? account.email;
      _userPhoto = account.photoUrl;

      await fetchEmails();
      await fetchLabels();
    } else {
      // OAuth unconfigured or cancelled — run in explicit demo mode.
      _isSignedIn = true;
      _isDemoMode = true;
      _userEmail = "demo@nomail.app";
      _userName = "Demo User";
      _userPhoto = null;
      await _loadDemoData();
    }

    _isLoading = false;
    notifyListeners();
    return true;
  }

  Future<void> _loadDemoData() async {
    // Create demo emails
    _emails = [
      Email(
        id: '1',
        from: 'amazon@amazon.com',
        to: 'demo@nomail.app',
        subject: 'Your order has been delivered',
        body: 'Your package containing iPhone 15 Pro has been delivered to your address.',
        snippet: 'Your package containing iPhone 15 Pro has been delivered...',
        date: DateTime.now().subtract(const Duration(hours: 2)),
        labels: ['CATEGORY_UPDATES'],
        isRead: false,
        isStarred: true,
        isImportant: true,
        hasAttachments: false,
        attachments: [],
        category: EmailCategory.shopping,
        aiImportanceScore: 0.9,
        aiSummary: 'iPhone 15 Pro delivered today',
        aiKeywords: ['delivery', 'order', 'iPhone'],
      ),
      Email(
        id: '2',
        from: 'netflix@netflix.com',
        to: 'demo@nomail.app',
        subject: 'Your Netflix subscription renewal',
        body: 'Your Netflix subscription will renew on January 1, 2025 for \$15.99/month.',
        snippet: 'Your Netflix subscription will renew on January 1...',
        date: DateTime.now().subtract(const Duration(days: 1)),
        labels: ['CATEGORY_PROMOTIONS'],
        isRead: true,
        isStarred: false,
        isImportant: false,
        hasAttachments: false,
        attachments: [],
        category: EmailCategory.finance,
        aiImportanceScore: 0.7,
        aiSummary: 'Netflix renewal: \$15.99/month',
        aiKeywords: ['subscription', 'renewal', 'payment'],
      ),
      Email(
        id: '3',
        from: 'utility@electriccompany.com',
        to: 'demo@nomail.app',
        subject: 'Electricity Bill - Due December 15',
        body: 'Your electricity bill of \$125.50 is due on December 15, 2024.',
        snippet: 'Your electricity bill of \$125.50 is due...',
        date: DateTime.now().subtract(const Duration(days: 2)),
        labels: [],
        isRead: false,
        isStarred: false,
        isImportant: true,
        hasAttachments: true,
        attachments: [
          EmailAttachment(
            filename: 'bill_december.pdf',
            mimeType: 'application/pdf',
            size: 245000,
          ),
        ],
        category: EmailCategory.finance,
        aiImportanceScore: 0.85,
        aiSummary: 'Electric bill \$125.50 due Dec 15',
        aiKeywords: ['bill', 'payment', 'due'],
      ),
    ];
    
    // Create demo insights
    _amazonOrders = [
      AmazonOrder(
        orderId: 'AMZ-123456',
        orderDate: DateTime.now().subtract(const Duration(days: 3)),
        amount: 999.99,
        status: 'Delivered',
        items: ['iPhone 15 Pro - Space Black'],
        deliveryDate: DateTime.now(),
      ),
      AmazonOrder(
        orderId: 'AMZ-123457',
        orderDate: DateTime.now().subtract(const Duration(days: 5)),
        amount: 49.99,
        status: 'In Transit',
        items: ['USB-C Cable', 'Phone Case'],
        deliveryDate: DateTime.now().add(const Duration(days: 2)),
        trackingNumber: 'TRK123456789',
      ),
    ];
    
    _subscriptions = [
      Subscription(
        service: 'Netflix',
        monthlyAmount: 15.99,
        nextBillingDate: DateTime.now().add(const Duration(days: 10)),
        status: 'Active',
        yearlyProjection: 191.88,
      ),
      Subscription(
        service: 'Spotify',
        monthlyAmount: 9.99,
        nextBillingDate: DateTime.now().add(const Duration(days: 15)),
        status: 'Active',
        yearlyProjection: 119.88,
      ),
      Subscription(
        service: 'Adobe Creative Cloud',
        monthlyAmount: 54.99,
        nextBillingDate: DateTime.now().add(const Duration(days: 5)),
        status: 'Active',
        yearlyProjection: 659.88,
      ),
    ];
    
    _bills = [
      Bill(
        provider: 'Electric Company',
        category: 'Utilities',
        amount: 125.50,
        dueDate: DateTime.now().add(const Duration(days: 10)),
        isPaid: false,
        accountNumber: 'ACC-12345',
      ),
      Bill(
        provider: 'Internet Provider',
        category: 'Utilities',
        amount: 79.99,
        dueDate: DateTime.now().add(const Duration(days: 5)),
        isPaid: false,
        accountNumber: 'INT-67890',
      ),
      Bill(
        provider: 'Water Company',
        category: 'Utilities',
        amount: 45.00,
        dueDate: DateTime.now().subtract(const Duration(days: 20)),
        isPaid: true,
        accountNumber: 'WAT-11111',
      ),
    ];
    
    _labels = ['Important', 'Work', 'Personal', 'Finance', 'Shopping'];
  }

  /// Legacy-widget entry point: refresh inbox and re-run AI analysis.
  Future<void> fetchAndAnalyzeEmails() => fetchEmails();

  Future<void> signOut() async {
    await _gmailService.signOut();
    _isSignedIn = false;
    _isDemoMode = false;
    _userEmail = null;
    _userName = null;
    _userPhoto = null;
    _emails.clear();
    _filteredEmails.clear();
    _threads.clear();
    _labels.clear();
    notifyListeners();
  }

  Future<void> fetchEmails({EmailFilter? filter, int maxResults = 50}) async {
    if (_isDemoMode) return; // demo data is static

    _isLoading = true;
    notifyListeners();

    try {
      _emails = await _gmailService.fetchEmails(
        filter: filter ?? _currentFilter,
        maxResults: maxResults,
      );
      
      await _enhanceEmailsWithAI();
      _sortEmailsByImportance();
    } catch (e) {
      print('Error fetching emails: $e');
    }

    _isLoading = false;
    notifyListeners();
  }

  Future<void> _enhanceEmailsWithAI() async {
    if (_emails.isEmpty) return;

    try {
      final emailContents = _emails.take(20).map((e) => 
        'Subject: ${e.subject}\nFrom: ${e.from}\nBody: ${e.snippet}'
      ).toList();

      final insights = await _aiService.analyzeEmails(emailContents);
      
      for (int i = 0; i < _emails.length && i < 20; i++) {
        final email = _emails[i];
        
        final importance = _calculateImportance(email);
        final summary = await _generateSummary(email);
        final keywords = _extractKeywords(email);
        
        _emails[i] = email.copyWith(
          aiImportanceScore: importance,
          aiSummary: summary,
          aiKeywords: keywords,
        );
      }
    } catch (e) {
      print('Error enhancing emails with AI: $e');
    }
  }

  double _calculateImportance(Email email) {
    double score = 0.5;
    
    if (email.isImportant) score += 0.2;
    if (email.isStarred) score += 0.1;
    if (email.from.contains('boss') || email.from.contains('manager')) score += 0.2;
    if (email.subject.toLowerCase().contains('urgent')) score += 0.3;
    if (email.subject.toLowerCase().contains('meeting')) score += 0.1;
    if (email.category == EmailCategory.finance) score += 0.15;
    if (email.hasAttachments) score += 0.05;
    
    return score.clamp(0.0, 1.0);
  }

  Future<String> _generateSummary(Email email) async {
    if (email.body.length < 100) return email.snippet;
    
    final words = email.body.split(' ');
    if (words.length > 50) {
      return words.take(50).join(' ') + '...';
    }
    return email.snippet;
  }

  List<String> _extractKeywords(Email email) {
    final text = '${email.subject} ${email.body}'.toLowerCase();
    final keywords = <String>[];
    
    final importantWords = [
      'meeting', 'deadline', 'urgent', 'payment', 'invoice',
      'order', 'delivery', 'appointment', 'reminder', 'action',
      'review', 'approval', 'important', 'asap', 'today'
    ];
    
    for (final word in importantWords) {
      if (text.contains(word)) {
        keywords.add(word);
      }
    }
    
    return keywords.take(5).toList();
  }

  void _sortEmailsByImportance() {
    _emails.sort((a, b) {
      final aScore = a.aiImportanceScore ?? 0.5;
      final bScore = b.aiImportanceScore ?? 0.5;
      
      if (!a.isRead && b.isRead) return -1;
      if (a.isRead && !b.isRead) return 1;
      
      return bScore.compareTo(aScore);
    });
  }

  Future<void> searchEmails(String query) async {
    _isLoading = true;
    notifyListeners();

    try {
      final filter = EmailFilter(query: query);
      await fetchEmails(filter: filter);
    } catch (e) {
      print('Error searching emails: $e');
    }

    _isLoading = false;
    notifyListeners();
  }

  void applyFilter(EmailFilter filter) {
    _currentFilter = filter;
    _filterEmails();
    notifyListeners();
  }

  void filterByCategory(EmailCategory? category) {
    if (category == null) {
      _filteredEmails.clear();
    } else {
      _filteredEmails = _emails.where((e) => e.category == category).toList();
    }
    notifyListeners();
  }

  void _filterEmails() {
    if (_currentFilter == null) {
      _filteredEmails.clear();
      return;
    }

    _filteredEmails = _emails.where((email) {
      if (_currentFilter!.isUnread == true && email.isRead) return false;
      if (_currentFilter!.isStarred == true && !email.isStarred) return false;
      if (_currentFilter!.isImportant == true && !email.isImportant) return false;
      if (_currentFilter!.hasAttachments == true && !email.hasAttachments) return false;
      if (_currentFilter!.category != null && email.category != _currentFilter!.category) return false;
      
      return true;
    }).toList();
  }

  Future<void> markAsRead(String messageId) async {
    if (!_isDemoMode) await _gmailService.markAsRead(messageId);
    final index = _emails.indexWhere((e) => e.id == messageId);
    if (index != -1) {
      _emails[index] = _emails[index].copyWith(isRead: true);
      notifyListeners();
    }
  }

  Future<void> markAsUnread(String messageId) async {
    if (!_isDemoMode) await _gmailService.markAsUnread(messageId);
    final index = _emails.indexWhere((e) => e.id == messageId);
    if (index != -1) {
      _emails[index] = _emails[index].copyWith(isRead: false);
      notifyListeners();
    }
  }

  Future<void> toggleStar(String messageId, bool starred) async {
    if (!_isDemoMode) await _gmailService.toggleStar(messageId, starred);
    final index = _emails.indexWhere((e) => e.id == messageId);
    if (index != -1) {
      _emails[index] = _emails[index].copyWith(isStarred: starred);
      notifyListeners();
    }
  }

  Future<void> archiveEmail(String messageId) async {
    if (!_isDemoMode) await _gmailService.archiveEmail(messageId);
    _emails.removeWhere((e) => e.id == messageId);
    _filteredEmails.removeWhere((e) => e.id == messageId);
    notifyListeners();
  }

  Future<void> deleteEmail(String messageId) async {
    if (!_isDemoMode) await _gmailService.moveToTrash(messageId);
    _emails.removeWhere((e) => e.id == messageId);
    _filteredEmails.removeWhere((e) => e.id == messageId);
    notifyListeners();
  }

  Future<void> sendEmail({
    required String to,
    required String subject,
    required String body,
    String? replyToMessageId,
  }) async {
    await _gmailService.sendEmail(
      to: to,
      subject: subject,
      body: body,
      replyToMessageId: replyToMessageId,
    );
  }

  Future<EmailThread> fetchThread(String threadId) async {
    if (_threads.containsKey(threadId)) {
      return _threads[threadId]!;
    }

    final thread = await _gmailService.fetchThread(threadId);
    _threads[threadId] = thread;
    return thread;
  }

  Future<void> fetchLabels() async {
    if (_isDemoMode) return;
    try {
      _labels = await _gmailService.fetchLabels();
      notifyListeners();
    } catch (e) {
      print('Error fetching labels: $e');
    }
  }

  Future<void> createLabel(String name) async {
    await _gmailService.createLabel(name);
    await fetchLabels();
  }

  Future<void> applyLabel(String messageId, String labelName) async {
    await _gmailService.applyLabel(messageId, labelName);
  }

  double get totalMonthlySpend {
    double total = 0;
    for (final sub in _subscriptions) {
      total += sub.monthlyAmount;
    }
    return total;
  }

  double get projectedYearlySpend {
    return totalMonthlySpend * 12;
  }

  int get ordersInTransit {
    return _amazonOrders.where((order) => 
      order.status.toLowerCase().contains('transit') ||
      order.status.toLowerCase().contains('shipped')
    ).length;
  }

  int get unpaidBillsCount {
    return _bills.where((bill) => !bill.isPaid).length;
  }

  double get totalUnpaidBills {
    return _bills
      .where((bill) => !bill.isPaid)
      .fold(0, (sum, bill) => sum + bill.amount);
  }
}