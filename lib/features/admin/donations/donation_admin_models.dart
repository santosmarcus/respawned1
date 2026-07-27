import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

class DonationCampaign {
  final String id;
  final String title;
  final double targetAmount;
  final double collectedAmount;
  final Color backgroundColor;
  final String type; // 'donation' or 'sponsorship'
  final String description;
  final String animalName;
  final bool isDog;
  final Timestamp? date; // Expected End Date
  final String? imageUrl;
  final String? createdBy;
  final Timestamp? createdAt;
  final bool isActive;

  DonationCampaign({
    required this.id,
    required this.title,
    required this.targetAmount,
    required this.collectedAmount,
    required this.backgroundColor,
    required this.type,
    this.description = '',
    this.animalName = 'Select',
    this.isDog = true,
    this.date,
    this.imageUrl,
    this.createdBy,
    this.createdAt,
    this.isActive = true,
  });

  // Helper for UI to show formatted amount
  String get amount => "₱${targetAmount.toStringAsFixed(0)}";

  String get formattedEndDate {
    if (type == 'sponsorship' && date == null) return "Indefinite";
    if (date == null) return "N/A";
    final dt = date!.toDate();
    return "${dt.month}/${dt.day}/${dt.year}";
  }

  String get daysRemaining {
    if (!isActive) return "Ended";
    if (type == 'sponsorship' && date == null) return "Ongoing";
    if (date == null) return "N/A";
    final diff = date!.toDate().difference(DateTime.now()).inDays;
    if (diff < 0) return "Ended";
    if (diff == 0) return "Ends today";
    return "$diff days left";
  }

  Map<String, dynamic> toMap() {
    return {
      'title': title,
      'targetAmount': targetAmount,
      'collectedAmount': collectedAmount,
      'backgroundColor': backgroundColor.value,
      'type': type,
      'description': description,
      'animalName': animalName,
      'isDog': isDog,
      'date': date,
      'imageUrl': imageUrl,
      'createdBy': createdBy,
      'createdAt': createdAt ?? FieldValue.serverTimestamp(),
      'isActive': isActive,
    };
  }

  factory DonationCampaign.fromFirestore(DocumentSnapshot doc) {
    Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
    return DonationCampaign(
      id: doc.id,
      title: data['title'] ?? '',
      targetAmount: (data['targetAmount'] ?? 0).toDouble(),
      collectedAmount: (data['collectedAmount'] ?? 0).toDouble(),
      backgroundColor: Color(data['backgroundColor'] ?? 0xFFE2E0B5),
      type: data['type'] ?? 'donation',
      description: data['description'] ?? '',
      animalName: data['animalName'] ?? '',
      isDog: data['isDog'] ?? true,
      date: data['date'] is Timestamp ? data['date'] : null,
      imageUrl: data['imageUrl'],
      createdBy: data['createdBy'],
      createdAt: data['createdAt'],
      isActive: data['isActive'] ?? true,
    );
  }
}

class DonationHistoryRecord {
  final String id;
  final double amountValue;
  final String amountString;
  final String campaignId;
  final Timestamp? createdAt;
  final String date;
  final String donorName;
  final bool isAnonymous;
  final String itemDescription;
  final String method;
  final String organizer;
  final String refNumber;
  final Timestamp? timestamp;
  final Timestamp? nextChargeDate;
  final String type; // 'donation' or 'sponsorship' or 'inkind'
  final String userId;
  final String status;
  final String category;
  final String clarification;
  final String address;
  final String organizationName;

  DonationHistoryRecord({
    required this.id,
    required this.amountValue,
    required this.amountString,
    required this.campaignId,
    this.createdAt,
    required this.date,
    required this.donorName,
    required this.isAnonymous,
    required this.itemDescription,
    required this.method,
    required this.organizer,
    required this.refNumber,
    this.timestamp,
    this.nextChargeDate,
    required this.type,
    required this.userId,
    this.status = '',
    this.category = '',
    this.clarification = '',
    this.address = '',
    this.organizationName = '',
  });

  // Compatibility getters for UI
  String get title => isAnonymous ? "Anonymous User" : donorName;
  String get amount => amountString.isNotEmpty ? amountString : "₱${amountValue.toStringAsFixed(2)}";

  Map<String, dynamic> toMap() {
    return {
      'amount': amountValue,
      'amountString': amountString,
      'campaignId': campaignId,
      'createdAt': createdAt ?? FieldValue.serverTimestamp(),
      'date': date,
      'donorName': donorName,
      'isAnonymous': isAnonymous,
      'itemDescription': itemDescription,
      'method': method,
      'organizer': organizer,
      'refNumber': refNumber,
      'timestamp': timestamp,
      'nextChargeDate': nextChargeDate,
      'type': type,
      'userId': userId,
      'status': status,
      'category': category,
      'clarification': clarification,
      'address': address,
      'organizationName': organizationName,
    };
  }

  factory DonationHistoryRecord.fromFirestore(DocumentSnapshot doc) {
    Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
    return DonationHistoryRecord(
      id: doc.id,
      amountValue: (data['amount'] is num) ? (data['amount'] as num).toDouble() : 0.0,
      amountString: data['amountString'] ?? '',
      campaignId: data['campaignId'] ?? '',
      createdAt: data['createdAt'],
      date: data['date'] ?? '',
      donorName: data['donorName'] ?? '',
      isAnonymous: data['isAnonymous'] ?? false,
      itemDescription: data['itemDescription'] ?? '',
      method: data['method'] ?? '',
      organizer: data['organizer'] ?? '',
      refNumber: data['refNumber'] ?? '',
      timestamp: data['timestamp'],
      nextChargeDate: data['nextChargeDate'],
      type: data['type'] ?? 'donation',
      userId: data['userId'] ?? '',
      status: data['status'] ?? '',
      category: data['category'] ?? '',
      clarification: data['clarification'] ?? '',
      address: data['address'] ?? '',
      organizationName: data['organizationName'] ?? '',
    );
  }
}

class FundAllocation {
  final String id;
  final String title;
  final String category;
  final String amount;
  final String date;
  final String? imageUrl;
  final Timestamp? createdAt;
  final String? campaignId;

  FundAllocation({
    required this.id,
    required this.title,
    required this.category,
    required this.amount,
    required this.date,
    this.imageUrl,
    this.createdAt,
    this.campaignId,
  });

  Map<String, dynamic> toMap() {
    return {
      'title': title,
      'category': category,
      'amount': amount,
      'date': date,
      'imageUrl': imageUrl,
      'createdAt': createdAt ?? FieldValue.serverTimestamp(),
      'campaignId': campaignId,
    };
  }

  factory FundAllocation.fromFirestore(DocumentSnapshot doc) {
    Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
    return FundAllocation(
      id: doc.id,
      title: data['title'] ?? '',
      category: data['category'] ?? '',
      amount: data['amount'] ?? '',
      date: data['date'] ?? '',
      imageUrl: data['imageUrl'],
      createdAt: data['createdAt'],
      campaignId: data['campaignId'],
    );
  }
}
