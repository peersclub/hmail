import 'package:flutter/foundation.dart';
import '../services/gmail_service.dart';
import '../services/ai_service.dart';
import '../models/email_insight.dart';
import 'package:googleapis/gmail/v1.dart';

class EmailProvider extends ChangeNotifier {
  final GmailService _gmailService = GmailService();
  final AIService _aiService = AIService();

  bool _isLoading = false;
  bool _isSignedIn = false;
  String? _userEmail;
  String? _userName;
  String? _userPhoto;

  List<EmailInsight> _insights = [];
  List<AmazonOrder> _amazonOrders = [];
  List<Subscription> _subscriptions = [];
  List<Bill> _bills = [];
  Map<String, dynamic> _spendingProjections = {};

  bool get isLoading => _isLoading;
  bool get isSignedIn => _isSignedIn;
  String? get userEmail => _userEmail;
  String? get userName => _userName;
  String? get userPhoto => _userPhoto;
  List<EmailInsight> get insights => _insights;
  List<AmazonOrder> get amazonOrders => _amazonOrders;
  List<Subscription> get subscriptions => _subscriptions;
  List<Bill> get bills => _bills;
  Map<String, dynamic> get spendingProjections => _spendingProjections;

  Future<bool> signIn() async {
    _isLoading = true;
    notifyListeners();

    final success = await _gmailService.signIn();
    if (success) {
      _isSignedIn = true;
      _userEmail = _gmailService.userEmail;
      _userName = _gmailService.userName;
      _userPhoto = _gmailService.userPhoto;
    }

    _isLoading = false;
    notifyListeners();
    return success;
  }

  Future<void> signOut() async {
    await _gmailService.signOut();
    _isSignedIn = false;
    _userEmail = null;
    _userName = null;
    _userPhoto = null;
    _insights.clear();
    _amazonOrders.clear();
    _subscriptions.clear();
    _bills.clear();
    _spendingProjections.clear();
    notifyListeners();
  }

  Future<void> fetchAndAnalyzeEmails() async {
    if (!_isSignedIn) return;

    _isLoading = true;
    notifyListeners();

    try {
      final futures = await Future.wait([
        _gmailService.fetchAmazonOrders(),
        _gmailService.fetchSubscriptions(),
        _gmailService.fetchBills(),
      ]);

      final amazonEmails = futures[0];
      final subscriptionEmails = futures[1];
      final billEmails = futures[2];

      final allEmailContents = <String>[];
      
      for (final email in [...amazonEmails, ...subscriptionEmails, ...billEmails]) {
        final body = _gmailService.extractEmailBody(email);
        final subject = _gmailService.extractEmailSubject(email);
        if (body != null || subject != null) {
          allEmailContents.add('Subject: ${subject ?? ""}\nBody: ${body ?? ""}');
        }
      }

      if (allEmailContents.isNotEmpty) {
        _insights = await _aiService.analyzeEmails(allEmailContents);
        
        _processInsights();
        
        _spendingProjections = await _aiService.generateSpendingProjections(
          _subscriptions,
          _bills,
        );
      }
    } catch (e) {
      print('Error fetching and analyzing emails: $e');
    }

    _isLoading = false;
    notifyListeners();
  }

  void _processInsights() {
    _amazonOrders.clear();
    _subscriptions.clear();
    _bills.clear();

    for (final insight in _insights) {
      switch (insight.category.toLowerCase()) {
        case 'amazon_orders':
        case 'amazon':
          if (insight.metadata != null) {
            _amazonOrders.add(AmazonOrder(
              orderId: insight.metadata!['orderId'] ?? 'Unknown',
              orderDate: insight.date ?? DateTime.now(),
              amount: (insight.value ?? 0).toDouble(),
              status: insight.metadata!['status'] ?? 'Unknown',
              items: List<String>.from(insight.metadata!['items'] ?? []),
              deliveryDate: insight.metadata!['deliveryDate'] != null 
                ? DateTime.tryParse(insight.metadata!['deliveryDate'])
                : null,
              trackingNumber: insight.metadata!['trackingNumber'],
            ));
          }
          break;
        
        case 'subscriptions':
        case 'subscription':
          if (insight.metadata != null) {
            _subscriptions.add(Subscription(
              service: insight.title,
              monthlyAmount: (insight.value ?? 0).toDouble(),
              nextBillingDate: insight.date,
              status: insight.metadata!['status'] ?? 'Active',
              yearlyProjection: (insight.value ?? 0).toDouble() * 12,
            ));
          }
          break;
        
        case 'bills':
        case 'bill':
          if (insight.metadata != null) {
            _bills.add(Bill(
              provider: insight.title,
              category: insight.metadata!['category'] ?? 'General',
              amount: (insight.value ?? 0).toDouble(),
              dueDate: insight.date ?? DateTime.now(),
              isPaid: insight.metadata!['isPaid'] ?? false,
              accountNumber: insight.metadata!['accountNumber'],
            ));
          }
          break;
      }
    }
  }

  int get ordersInTransit {
    return _amazonOrders.where((order) => 
      order.status.toLowerCase().contains('transit') ||
      order.status.toLowerCase().contains('shipped')
    ).length;
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

  int get unpaidBillsCount {
    return _bills.where((bill) => !bill.isPaid).length;
  }

  double get totalUnpaidBills {
    return _bills
      .where((bill) => !bill.isPaid)
      .fold(0, (sum, bill) => sum + bill.amount);
  }
}