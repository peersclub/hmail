import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/enhanced_email_provider.dart';

class LoginScreen extends StatelessWidget {
  const LoginScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Theme.of(context).colorScheme.primary,
              Theme.of(context).colorScheme.secondary,
            ],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(32.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.mail_outline,
                    size: 100,
                    color: Colors.white,
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'NoMail',
                    style: Theme.of(context).textTheme.displayMedium?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Smart Email Insights',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      color: Colors.white70,
                    ),
                  ),
                  const SizedBox(height: 48),
                  Card(
                    elevation: 8,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(24.0),
                      child: Column(
                        children: [
                          Text(
                            'Sign in to get started',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'Analyze your Gmail to get insights on:',
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                          const SizedBox(height: 12),
                          _buildFeature(Icons.shopping_cart, 'Amazon orders & tracking'),
                          _buildFeature(Icons.subscriptions, 'Subscriptions & recurring payments'),
                          _buildFeature(Icons.receipt_long, 'Bills & expenses'),
                          _buildFeature(Icons.insights, 'Spending projections'),
                          const SizedBox(height: 24),
                          Consumer<EnhancedEmailProvider>(
                            builder: (context, provider, _) {
                              return provider.isLoading
                                ? const CircularProgressIndicator()
                                : ElevatedButton.icon(
                                    onPressed: () async {
                                      await provider.signIn();
                                    },
                                    icon: const Icon(
                                      Icons.login,
                                      size: 24,
                                    ),
                                    label: const Padding(
                                      padding: EdgeInsets.symmetric(
                                        horizontal: 16,
                                        vertical: 12,
                                      ),
                                      child: Text('Sign in with Google'),
                                    ),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.white,
                                      foregroundColor: Colors.black87,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(8),
                                        side: BorderSide(color: Colors.grey.shade300),
                                      ),
                                    ),
                                  );
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFeature(IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, size: 20, color: Colors.blue),
          const SizedBox(width: 12),
          Text(text, style: const TextStyle(fontSize: 14)),
        ],
      ),
    );
  }
}