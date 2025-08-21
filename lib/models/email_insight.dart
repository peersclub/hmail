class EmailInsight {
  final String category;
  final String title;
  final String description;
  final dynamic value;
  final DateTime? date;
  final Map<String, dynamic>? metadata;

  EmailInsight({
    required this.category,
    required this.title,
    required this.description,
    this.value,
    this.date,
    this.metadata,
  });

  factory EmailInsight.fromJson(Map<String, dynamic> json) {
    return EmailInsight(
      category: json['category'],
      title: json['title'],
      description: json['description'],
      value: json['value'],
      date: json['date'] != null ? DateTime.parse(json['date']) : null,
      metadata: json['metadata'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'category': category,
      'title': title,
      'description': description,
      'value': value,
      'date': date?.toIso8601String(),
      'metadata': metadata,
    };
  }
}

class AmazonOrder {
  final String orderId;
  final DateTime orderDate;
  final double amount;
  final String status;
  final List<String> items;
  final DateTime? deliveryDate;
  final String? trackingNumber;

  AmazonOrder({
    required this.orderId,
    required this.orderDate,
    required this.amount,
    required this.status,
    required this.items,
    this.deliveryDate,
    this.trackingNumber,
  });
}

class Subscription {
  final String service;
  final double monthlyAmount;
  final DateTime? nextBillingDate;
  final String status;
  final double yearlyProjection;

  Subscription({
    required this.service,
    required this.monthlyAmount,
    this.nextBillingDate,
    required this.status,
    required this.yearlyProjection,
  });
}

class Bill {
  final String provider;
  final String category;
  final double amount;
  final DateTime dueDate;
  final bool isPaid;
  final String? accountNumber;

  Bill({
    required this.provider,
    required this.category,
    required this.amount,
    required this.dueDate,
    required this.isPaid,
    this.accountNumber,
  });
}