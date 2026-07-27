import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

enum CardType { visa, mastercard, other }

enum HistoryType { donation, inKindDonation, sponsorship }

enum InKindStatus { complete, inProgress, cancelled }

enum DonationStatus { active, funded, expired, closed }

enum RefundStatus { none, pending, approved, rejected }

class CreditCard {
  final String id;
  final CardType cardType;
  final String cardNumberLastFour;
  final String cardHolderName;
  final String expiryDate;
  final Color backgroundColor;
  final String? token; // PayMongo Payment Method ID

  CreditCard({
    this.id = '',
    required this.cardType,
    required this.cardNumberLastFour,
    required this.cardHolderName,
    required this.expiryDate,
    required this.backgroundColor,
    this.token,
  });

  factory CreditCard.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    final typeStr = (data['cardType'] ?? 'other').toString().toLowerCase();
    CardType type;
    if (typeStr == 'visa') {
      type = CardType.visa;
    } else if (typeStr == 'mastercard') {
      type = CardType.mastercard;
    } else {
      type = CardType.other;
    }

    return CreditCard(
      id: doc.id,
      cardType: type,
      cardNumberLastFour: data['cardNumberLastFour'] ?? '',
      cardHolderName: data['cardHolderName'] ?? '',
      expiryDate: data['expiryDate'] ?? '',
      backgroundColor: Color(data['backgroundColor'] ?? 0xFF1E1E1E),
      token: data['token'],
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'cardType': cardType.name,
      'cardNumberLastFour': cardNumberLastFour,
      'cardHolderName': cardHolderName,
      'expiryDate': expiryDate,
      'backgroundColor': backgroundColor.toARGB32(),
      'token': token,
      'createdAt': FieldValue.serverTimestamp(),
    };
  }
}

class DonationItem {
  final String description;
  final double amount;

  DonationItem({
    required this.description,
    required this.amount,
  });
}

class DonationReviewParams {
  final String fundraiserId;
  final String organizationName;
  final String donationMethod;
  final DonationItem item;
  final bool isAnonymous;
  final SponsorPet? pet;
  final DonationListing? sponsorship;
  final bool isSponsorship;

  DonationReviewParams({
    required this.fundraiserId,
    required this.organizationName,
    required this.donationMethod,
    required this.item,
    required this.isAnonymous,
    this.pet,
    this.sponsorship,
    this.isSponsorship = false,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DonationReviewParams &&
          runtimeType == other.runtimeType &&
          fundraiserId == other.fundraiserId &&
          organizationName == other.organizationName &&
          donationMethod == other.donationMethod &&
          item.amount == other.item.amount &&
          item.description == other.item.description &&
          isAnonymous == other.isAnonymous &&
          pet?.id == other.pet?.id &&
          sponsorship?.id == other.sponsorship?.id &&
          isSponsorship == other.isSponsorship;

  @override
  int get hashCode =>
      fundraiserId.hashCode ^
      organizationName.hashCode ^
      donationMethod.hashCode ^
      item.amount.hashCode ^
      item.description.hashCode ^
      isAnonymous.hashCode ^
      (pet?.id).hashCode ^
      (sponsorship?.id).hashCode ^
      isSponsorship.hashCode;
}

class InKindDonationReviewParams {
  final String fundraiserId;
  final String organizationName;
  final String category;
  final String clarification;
  final bool isAnonymous;
  final String address;

  InKindDonationReviewParams({
    required this.fundraiserId,
    required this.organizationName,
    required this.category,
    required this.clarification,
    required this.isAnonymous,
    required this.address,
  });
}

class DonationListing {
  final String id;
  final String title;
  final double target;
  final double collected;
  final String organizer;
  final DateTime? endDate;
  final String time;
  final String description;
  final int numdonated;
  final String address;
  final String type; // 'donation' or 'sponsorship'
  final DonationStatus status;
  final String? animalId;
  final String? animalName;
  final String? earmarkedAnimalId;
  final String? imageUrl;
  final Color backgroundColor;
  final List<InKindItem> inKindItems;
  final bool isDog;
  final bool isActive;
  final bool acceptInKind;
  final DateTime? createdAt;
  final String? createdBy;
  bool favorited;
  bool donated;

  DonationListing({
    required this.id,
    required this.title,
    required this.target,
    required this.collected,
    required this.organizer,
    this.endDate,
    required this.time,
    required this.description,
    required this.numdonated,
    required this.address,
    required this.type,
    this.status = DonationStatus.active,
    this.animalId,
    this.animalName,
    this.earmarkedAnimalId,
    this.imageUrl,
    this.backgroundColor = const Color(0xFFE2E0B5),
    this.inKindItems = const [],
    this.isDog = true,
    this.isActive = true,
    this.acceptInKind = false,
    this.createdAt,
    this.createdBy,
    this.favorited = false,
    this.donated = false,
  });

  int get percentage => target > 0 ? ((collected / target) * 100).toInt() : 0;

  int get daysRemaining {
    if (endDate == null) return 0;
    final now = DateTime.now();
    final diff = endDate!.difference(now);
    if (diff.isNegative) return 0;
    return (diff.inHours / 24).ceil();
  }

  bool get isEnded {
    if (!isActive || status == DonationStatus.closed || status == DonationStatus.funded) return true;
    if (endDate == null) return false;
    return endDate!.isBefore(DateTime.now());
  }

  factory DonationListing.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    DateTime? parsedEndDate;
    if (data['date'] is Timestamp) {
      parsedEndDate = (data['date'] as Timestamp).toDate();
    } else if (data['date'] is String) {
      // Handle legacy string dates if they exist
      try {
        final parts = (data['date'] as String).split('/');
        if (parts.length == 3) {
          parsedEndDate = DateTime(int.parse(parts[2]), int.parse(parts[0]), int.parse(parts[1]));
        }
      } catch (_) {}
    }

    DateTime? createdAt;
    if (data['createdAt'] is Timestamp) {
      createdAt = (data['createdAt'] as Timestamp).toDate();
    }

    final inKindData = data['inKindItems'] as List<dynamic>? ?? [];
    final inKindItems = inKindData.map((item) => InKindItem.fromMap(item as Map<String, dynamic>)).toList();

    final rawStatus = data['status'] as String? ?? 'active';
    DonationStatus status;
    switch (rawStatus.toLowerCase()) {
      case 'funded': status = DonationStatus.funded; break;
      case 'expired': status = DonationStatus.expired; break;
      case 'closed': status = DonationStatus.closed; break;
      default: status = DonationStatus.active;
    }

    return DonationListing(
      id: doc.id,
      title: data['title'] ?? '',
      target: (data['targetAmount'] ?? 0).toDouble(),
      collected: (data['collectedAmount'] ?? 0).toDouble(),
      organizer: data['organizer'] ?? 'Rescue Shelter',
      endDate: parsedEndDate,
      time: data['time'] ?? '9:00 AM - 10:30 AM',
      description: data['description'] ?? '',
      numdonated: (data['numdonors'] ?? 0).toInt(),
      address: data['address'] ?? 'Rescue Center',
      type: data['type'] ?? 'donation',
      status: status,
      animalId: data['animalId'],
      animalName: data['animalName'],
      earmarkedAnimalId: data['earmarkedAnimalId'],
      imageUrl: data['imageUrl'],
      backgroundColor: Color(data['backgroundColor'] ?? 0xFFE2E0B5),
      inKindItems: inKindItems,
      isDog: data['isDog'] ?? true,
      isActive: data['isActive'] ?? true,
      acceptInKind: data['acceptInKind'] ?? false,
      createdAt: createdAt,
      createdBy: data['createdBy'],
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'title': title,
      'targetAmount': target,
      'collectedAmount': collected,
      'organizer': organizer,
      'date': endDate != null ? Timestamp.fromDate(endDate!) : null,
      'time': time,
      'description': description,
      'numdonors': numdonated,
      'address': address,
      'type': type,
      'animalId': animalId,
      'animalName': animalName,
      'imageUrl': imageUrl,
      'backgroundColor': backgroundColor.toARGB32(),
      'inKindItems': inKindItems.map((e) => e.toMap()).toList(),
      'isDog': isDog,
      'isActive': isActive,
      'acceptInKind': acceptInKind,
      'createdAt': createdAt != null ? Timestamp.fromDate(createdAt!) : null,
      'createdBy': createdBy,
    };
  }
}

class InKindItem {
  final String category;
  final String description;

  InKindItem({
    required this.category,
    required this.description,
  });

  factory InKindItem.fromMap(Map<String, dynamic> map) {
    return InKindItem(
      category: map['category'] ?? '',
      description: map['description'] ?? '',
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'category': category,
      'description': description,
    };
  }
}

class SponsorPet {
  final String id;
  final String name;
  final String breed;
  final String age;
  final String description;
  final List<String> tags;
  final String? adoptionStatus;
  final String? coatLength;
  final List<String> health;
  final List<String> photoUrls;
  bool favorited;

  SponsorPet({
    required this.id,
    required this.name,
    required this.breed,
    required this.age,
    required this.description,
    required this.tags,
    this.adoptionStatus,
    this.coatLength,
    this.health = const [],
    this.photoUrls = const [],
    this.favorited = false,
  });

  factory SponsorPet.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return SponsorPet(
      id: doc.id,
      name: data['name'] ?? '',
      breed: data['breed'] ?? '',
      age: data['age']?.toString() ?? '',
      description: data['description'] ?? '',
      tags: List<String>.from(data['keyCharacteristics'] ?? []),
      adoptionStatus: data['adoptionStatus'],
      coatLength: data['coatLength'],
      health: List<String>.from(data['health'] ?? []),
      photoUrls: List<String>.from(data['photoUrls'] ?? []),
    );
  }
}

class HistoryItem {
  final String id;
  final HistoryType type;
  final String organizer;
  final DateTime dateTime;
  final String refNumber;
  final InKindStatus? status;

  // Monetary specific
  final String? donationMethod;
  final double? amount;
  final String? itemDescription;
  final String? campaignName;

  // In-kind specific
  final String? category;
  final String? clarification;
  final bool? isAnonymous;
  final String? address;

  final RefundStatus refundStatus;
  final bool isPublic;

  // Sponsorship specific
  final String? campaignId;
  final DateTime? nextChargeDate;
  final String? sponsorshipStatus; // 'active', 'cancelled', 'inactive'
  final SponsorPet? pet;
  final double? nextChargeAmount;

  HistoryItem({
    required this.id,
    required this.type,
    required this.organizer,
    required this.dateTime,
    required this.refNumber,
    this.status,
    this.donationMethod,
    this.amount,
    this.itemDescription,
    this.campaignName,
    this.category,
    this.clarification,
    this.isAnonymous,
    this.address,
    this.refundStatus = RefundStatus.none,
    this.isPublic = true,
    this.campaignId,
    this.nextChargeDate,
    this.sponsorshipStatus,
    this.pet,
    this.nextChargeAmount,
  });

  HistoryItem copyWith({
    String? id,
    HistoryType? type,
    String? organizer,
    DateTime? dateTime,
    String? refNumber,
    InKindStatus? status,
    String? donationMethod,
    double? amount,
    String? itemDescription,
    String? campaignName,
    String? category,
    String? clarification,
    bool? isAnonymous,
    String? address,
    RefundStatus? refundStatus,
    bool? isPublic,
    String? campaignId,
    DateTime? nextChargeDate,
    String? sponsorshipStatus,
    SponsorPet? pet,
    double? nextChargeAmount,
  }) {
    return HistoryItem(
      id: id ?? this.id,
      type: type ?? this.type,
      organizer: organizer ?? this.organizer,
      dateTime: dateTime ?? this.dateTime,
      refNumber: refNumber ?? this.refNumber,
      status: status ?? this.status,
      donationMethod: donationMethod ?? this.donationMethod,
      amount: amount ?? this.amount,
      itemDescription: itemDescription ?? this.itemDescription,
      campaignName: campaignName ?? this.campaignName,
      category: category ?? this.category,
      clarification: clarification ?? this.clarification,
      isAnonymous: isAnonymous ?? this.isAnonymous,
      address: address ?? this.address,
      refundStatus: refundStatus ?? this.refundStatus,
      isPublic: isPublic ?? this.isPublic,
      campaignId: campaignId ?? this.campaignId,
      nextChargeDate: nextChargeDate ?? this.nextChargeDate,
      sponsorshipStatus: sponsorshipStatus ?? this.sponsorshipStatus,
      pet: pet ?? this.pet,
      nextChargeAmount: nextChargeAmount ?? this.nextChargeAmount,
    );
  }

  factory HistoryItem.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    
    // Robust type mapping
    final rawType = data['type'] as String? ?? 'donation';
    HistoryType type;
    if (rawType == 'inkind' || rawType == 'inKindDonation') {
      type = HistoryType.inKindDonation;
    } else if (rawType == 'sponsorship') {
      type = HistoryType.sponsorship;
    } else {
      type = HistoryType.donation;
    }
    
    // Robust status mapping for In-Kind
    InKindStatus? inKindStatus;
    if (type == HistoryType.inKindDonation) {
      final rawStatus = (data['status'] as String? ?? '').toLowerCase();
      if (rawStatus == 'complete' || rawStatus == 'completed') {
        inKindStatus = InKindStatus.complete;
      } else if (rawStatus == 'cancelled') {
        inKindStatus = InKindStatus.cancelled;
      } else {
        inKindStatus = InKindStatus.inProgress; // Default to inProgress if inkind
      }
    }
    
    final rawRefund = data['refundStatus'] as String? ?? 'none';
    RefundStatus refundStatus;
    switch (rawRefund.toLowerCase()) {
      case 'pending': refundStatus = RefundStatus.pending; break;
      case 'approved': refundStatus = RefundStatus.approved; break;
      case 'rejected': refundStatus = RefundStatus.rejected; break;
      default: refundStatus = RefundStatus.none;
    }

    return HistoryItem(
      id: doc.id,
      type: type,
      organizer: data['organizer'] ?? data['organizationName'] ?? '',
      dateTime: (data['timestamp'] as Timestamp?)?.toDate() ?? DateTime.now(),
      refNumber: data['refNumber'] ?? '',
      status: inKindStatus,
      donationMethod: data['donationMethod'],
      amount: (data['amount'] ?? 0).toDouble(),
      itemDescription: data['itemDescription'],
      campaignName: data['campaignName'] ?? data['title'] ?? data['campaignTitle'],
      category: data['category'],
      clarification: data['clarification'],
      isAnonymous: data['isAnonymous'],
      address: data['address'],
      refundStatus: refundStatus,
      isPublic: data['isPublic'] ?? true,
      campaignId: data['campaignId'],
      nextChargeDate: data['nextChargeDate'] != null ? (data['nextChargeDate'] as Timestamp).toDate() : null,
      sponsorshipStatus: data['sponsorshipStatus'] ?? (rawType == 'sponsorship' ? 'active' : null),
      pet: data['pet'] != null ? SponsorPet.fromFirestore(data['pet']) : null, 
      nextChargeAmount: (data['nextChargeAmount'] ?? 0).toDouble(),
    );
  }

  bool get isOverdue {
    if (type != HistoryType.sponsorship || sponsorshipStatus != 'active' || nextChargeDate == null) return false;
    return DateTime.now().isAfter(nextChargeDate!);
  }
}
