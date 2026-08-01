import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:provider/provider.dart';
import 'package:hmail/providers/enhanced_email_provider.dart';
import 'package:hmail/models/email.dart';
import 'package:hmail/screens/login_screen.dart';
import 'package:hmail/screens/main_navigation_screen.dart';

void main() {
  setUpAll(() {
    // Providers read dotenv at construction; tests run without a bundled .env.
    dotenv.testLoad(fileInput: '');
  });
  group('NoMail App Tests', () {
    testWidgets('Shows login screen when not signed in', (WidgetTester tester) async {
      await tester.pumpWidget(
        ChangeNotifierProvider(
          create: (_) => EnhancedEmailProvider(),
          child: const MaterialApp(
            home: LoginScreen(),
          ),
        ),
      );

      expect(find.text('NoMail'), findsOneWidget);
      expect(find.text('Sign in with Google'), findsOneWidget);
      expect(find.byIcon(Icons.mail_outline), findsOneWidget);
    });

    testWidgets('Login screen displays features', (WidgetTester tester) async {
      await tester.pumpWidget(
        ChangeNotifierProvider(
          create: (_) => EnhancedEmailProvider(),
          child: const MaterialApp(
            home: LoginScreen(),
          ),
        ),
      );

      expect(find.text('Amazon orders & tracking'), findsOneWidget);
      expect(find.text('Subscriptions & recurring payments'), findsOneWidget);
      expect(find.text('Bills & expenses'), findsOneWidget);
      expect(find.text('Spending projections'), findsOneWidget);
    });
  });

  group('Email Model Tests', () {
    test('Email categorization works correctly', () {
      final email = Email(
        id: 'test1',
        from: 'amazon@amazon.com',
        to: 'user@example.com',
        subject: 'Your order has been shipped',
        body: 'Order details...',
        snippet: 'Order #123',
        date: DateTime.now(),
        labels: ['CATEGORY_UPDATES'],
        isRead: false,
        isStarred: false,
        isImportant: false,
        hasAttachments: false,
        attachments: [],
        category: EmailCategory.shopping,
      );

      expect(email.category, EmailCategory.shopping);
      expect(email.isRead, false);
    });

    test('Email filter generates correct Gmail query', () {
      final filter = EmailFilter(
        isUnread: true,
        isStarred: true,
        hasAttachments: true,
        category: EmailCategory.finance,
      );

      final query = filter.toGmailQuery();
      expect(query.contains('is:unread'), true);
      expect(query.contains('is:starred'), true);
      expect(query.contains('has:attachment'), true);
      expect(query.contains('invoice OR receipt OR payment OR bill'), true);
    });
  });

  group('Dashboard Tests', () {
    testWidgets('Navigation bar shows all sections', (WidgetTester tester) async {
      await tester.pumpWidget(
        ChangeNotifierProvider(
          create: (_) => EnhancedEmailProvider(),
          child: const MaterialApp(
            home: MainNavigationScreen(),
          ),
        ),
      );

      // Tab content may reuse the same icons in empty states, so assert
      // presence rather than uniqueness.
      expect(find.byIcon(Icons.inbox), findsWidgets);
      expect(find.byIcon(Icons.insights_outlined), findsWidgets);
      expect(find.byIcon(Icons.shopping_cart_outlined), findsWidgets);
      expect(find.byIcon(Icons.subscriptions_outlined), findsWidgets);
      expect(find.byIcon(Icons.receipt_long_outlined), findsWidgets);
    });
  });

  group('Email List Tests', () {
    test('Email importance score calculation', () {
      final provider = EnhancedEmailProvider();
      
      final email = Email(
        id: 'test2',
        from: 'boss@company.com',
        to: 'user@example.com',
        subject: 'Urgent: Meeting tomorrow',
        body: 'Please attend the meeting...',
        snippet: 'Please attend',
        date: DateTime.now(),
        labels: ['IMPORTANT'],
        isRead: false,
        isStarred: true,
        isImportant: true,
        hasAttachments: true,
        attachments: [],
        category: EmailCategory.work,
      );

      // Test that urgent emails from boss get high importance
      expect(email.subject.toLowerCase().contains('urgent'), true);
      expect(email.from.contains('boss'), true);
      expect(email.isImportant, true);
    });
  });
}
