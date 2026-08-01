import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import '../models/email_insight.dart';

class AIService {
  final Dio _dio = Dio();
  late String? _claudeApiKey;
  late String? _openAiApiKey;

  AIService() {
    _claudeApiKey = _nonEmpty(dotenv.env['CLAUDE_API_KEY']);
    _openAiApiKey = _nonEmpty(dotenv.env['OPENAI_API_KEY']);
  }

  static String? _nonEmpty(String? value) =>
      (value == null || value.trim().isEmpty) ? null : value.trim();

  Future<List<EmailInsight>> analyzeEmails(List<String> emailContents) async {
    if (_claudeApiKey == null && _openAiApiKey == null) {
      throw Exception('No AI API keys configured');
    }

    final combinedContent = emailContents.take(20).join('\n---\n');
    
    final prompt = '''
    Analyze the following emails and extract insights in these categories:
    1. Amazon Orders: Order IDs, items, amounts, delivery status, tracking info
    2. Subscriptions: Service names, monthly costs, renewal dates, yearly projections
    3. Bills: Provider, category, amount, due dates, payment status
    4. Travel: Bookings, flights, hotels, upcoming trips
    5. Financial: Transactions, statements, alerts
    6. Shopping: Other e-commerce orders, receipts
    
    Provide structured JSON output with insights for each category found.
    Focus on actionable insights and spending patterns.
    
    Emails:
    $combinedContent
    
    Return JSON format:
    {
      "insights": [
        {
          "category": "category_name",
          "title": "insight_title",
          "description": "detailed_description",
          "value": numeric_or_string_value,
          "date": "ISO_date_if_applicable",
          "metadata": {}
        }
      ],
      "summary": {
        "total_orders": 0,
        "orders_in_transit": 0,
        "monthly_subscriptions": 0,
        "projected_monthly_spend": 0,
        "upcoming_bills": 0,
        "total_bills_amount": 0
      }
    }
    ''';

    try {
      if (_claudeApiKey != null) {
        return await _analyzeWithClaude(prompt);
      } else if (_openAiApiKey != null) {
        return await _analyzeWithOpenAI(prompt);
      }
      return [];
    } catch (e) {
      print('Error analyzing emails: $e');
      return [];
    }
  }

  Future<List<EmailInsight>> _analyzeWithClaude(String prompt) async {
    final response = await _dio.post(
      'https://api.anthropic.com/v1/messages',
      options: Options(
        headers: {
          'Content-Type': 'application/json',
          'x-api-key': _claudeApiKey,
          'anthropic-version': '2023-06-01',
        },
      ),
      data: {
        'model': 'claude-haiku-4-5',
        'max_tokens': 4000,
        'messages': [
          {
            'role': 'user',
            'content': prompt,
          }
        ],
        'temperature': 0.3,
      },
    );

    final content = response.data['content'][0]['text'];
    return _parseInsights(content);
  }

  Future<List<EmailInsight>> _analyzeWithOpenAI(String prompt) async {
    final response = await _dio.post(
      'https://api.openai.com/v1/chat/completions',
      options: Options(
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $_openAiApiKey',
        },
      ),
      data: {
        'model': 'gpt-3.5-turbo',
        'messages': [
          {
            'role': 'system',
            'content': 'You are an AI assistant that analyzes emails and extracts structured insights. Always respond with valid JSON.',
          },
          {
            'role': 'user',
            'content': prompt,
          }
        ],
        'temperature': 0.3,
        'response_format': {'type': 'json_object'},
      },
    );

    final content = response.data['choices'][0]['message']['content'];
    return _parseInsights(content);
  }

  List<EmailInsight> _parseInsights(String jsonContent) {
    try {
      final json = jsonDecode(jsonContent);
      final insights = json['insights'] as List;
      return insights.map((i) => EmailInsight.fromJson(i)).toList();
    } catch (e) {
      print('Error parsing insights: $e');
      return [];
    }
  }

  Future<Map<String, dynamic>> generateSpendingProjections(
    List<Subscription> subscriptions,
    List<Bill> bills,
  ) async {
    double monthlySubscriptions = 0;
    double monthlyBills = 0;

    for (final sub in subscriptions) {
      monthlySubscriptions += sub.monthlyAmount;
    }

    for (final bill in bills) {
      monthlyBills += bill.amount;
    }

    return {
      'monthly_subscriptions': monthlySubscriptions,
      'yearly_subscriptions': monthlySubscriptions * 12,
      'monthly_bills': monthlyBills,
      'yearly_bills': monthlyBills * 12,
      'total_monthly': monthlySubscriptions + monthlyBills,
      'total_yearly': (monthlySubscriptions + monthlyBills) * 12,
    };
  }
}