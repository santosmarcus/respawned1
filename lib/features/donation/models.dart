import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

enum CardType { visa, mastercard, other }

enum HistoryType { donation, inKindDonation, sponsorship }

enum InKindStatus { complete, inProgress, cancelled }

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
      'backgroundColor': backgroundColor.value,
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
  final String? animalId;
  final String? animalName;
  final String? imageUrl;
  final Color backgroundColor;
  final List<InKindItem> inKindItems;
  final bool isDog;
  final bool isActive;
  final bool acceptInKind;
  final DateTime? createdAt;
  final String? createdBy;

  // Admin lifecycle & finance fields (written by functions/campaigns.js).
  // All optional: listings created before the admin module still parse.
  /// 'draft' | 'active' | 'paused' | 'goal_met' | 'goal_not_met' | 'closed'
  final String status;
  /// 'campaign' | 'animal' | 'medical' | 'shelter_resource' | 'general'
  final String fundKind;
  final List<String> purposeTags;
  final bool restricted;
  final double? monthlyAmount;
  final String? intendedUse;
  final double allocatedAmount;
  final double transferredOutAmount;
  final double transferredInAmount;
  final bool needsExtensionDecision;
  final int extensionCount;
  final String? organizationId;
  final String? linkedCaseId;
  final DateTime? startDate;
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
    this.animalId,
    this.animalName,
    this.imageUrl,
    this.backgroundColor = const Color(0xFFE2E0B5),
    this.inKindItems = const [],
    this.isDog = true,
    this.isActive = true,
    this.acceptInKind = false,
    this.createdAt,
    this.createdBy,
    this.status = 'active',
    this.fundKind = 'campaign',
    this.purposeTags = const [],
    this.restricted = false,
    this.monthlyAmount,
    this.intendedUse,
    this.allocatedAmount = 0,
    this.transferredOutAmount = 0,
    this.transferredInAmount = 0,
    this.needsExtensionDecision = false,
    this.extensionCount = 0,
    this.organizationId,
    this.linkedCaseId,
    this.startDate,
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
    if (!isActive) return true;
    if (endDate == null) return false;
    return endDate!.isBefore(DateTime.now());
  }

  /// Unpublished admin drafts — never shown in the general view.
  bool get isDraft => status == 'draft';

  /// collected + transferred in − transferred out − allocated. Transfers in
  /// are existing funds moved from another campaign, never donations.
  double get availableBalance => collected + transferredInAmount - transferredOutAmount - allocatedAmount;

  /// Verified collections above the goal not yet moved elsewhere (capped by
  /// what is still available). Mirrors moneyOf() in functions/campaigns.js;
  /// the backend recomputes it before any transfer.
  double get eligibleExcess {
    if (target <= 0 || collected <= target) return 0;
    final excess = collected - target - transferredOutAmount;
    final capped = excess < availableBalance ? excess : availableBalance;
    return capped > 0 ? capped : 0;
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

    double money(String key) => (data[key] is num) ? (data[key] as num).toDouble() : 0;
    final isActive = data['isActive'] ?? true;
    // Listings created before the admin module have no `status`.
    final status = (data['status'] is String && (data['status'] as String).isNotEmpty)
        ? data['status'] as String
        : (isActive == false ? 'closed' : 'active');

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
      animalId: data['animalId'],
      animalName: data['animalName'],
      imageUrl: data['imageUrl'],
      backgroundColor: Color(data['backgroundColor'] ?? 0xFFE2E0B5),
      inKindItems: inKindItems,
      isDog: data['isDog'] ?? true,
      isActive: isActive,
      acceptInKind: data['acceptInKind'] ?? false,
      createdAt: createdAt,
      createdBy: data['createdBy'],
      status: status,
      fundKind: data['fundKind'] as String? ?? ((data['type'] ?? 'donation') == 'sponsorship' ? 'animal' : 'campaign'),
      purposeTags: List<String>.from(data['purposeTags'] ?? const []),
      restricted: data['restricted'] == true,
      monthlyAmount: (data['monthlyAmount'] is num) ? (data['monthlyAmount'] as num).toDouble() : null,
      intendedUse: data['intendedUse'] as String?,
      allocatedAmount: money('allocatedAmount'),
      transferredOutAmount: money('transferredOutAmount'),
      transferredInAmount: money('transferredInAmount'),
      needsExtensionDecision: data['needsExtensionDecision'] == true,
      extensionCount: (data['extensionCount'] is num) ? (data['extensionCount'] as num).toInt() : 0,
      organizationId: data['organizationId'] as String?,
      linkedCaseId: data['linkedCaseId'] as String?,
      startDate: data['startDate'] is Timestamp ? (data['startDate'] as Timestamp).toDate() : null,
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
      'backgroundColor': backgroundColor.value,
      'inKindItems': inKindItems.map((e) => e.toMap()).toList(),
      'isDog': isDog,
      'isActive': isActive,
      'acceptInKind': acceptInKind,
      'createdAt': createdAt != null ? Timestamp.fromDate(createdAt!) : null,
      'createdBy': createdBy,
      'status': status,
      'fundKind': fundKind,
      'purposeTags': purposeTags,
      'restricted': restricted,
      'monthlyAmount': monthlyAmount,
      'intendedUse': intendedUse,
      'allocatedAmount': allocatedAmount,
      'transferredOutAmount': transferredOutAmount,
      'transferredInAmount': transferredInAmount,
      'needsExtensionDecision': needsExtensionDecision,
      'extensionCount': extensionCount,
      'organizationId': organizationId,
      'linkedCaseId': linkedCaseId,
      'startDate': startDate != null ? Timestamp.fromDate(startDate!) : null,
    };
  }
}

class InKindItem {
  final String category;
  final String description;
  // Optional (admin module). Pledges stay in donations/ (status 'inprogress')
  // until an admin confirms receipt, which increments quantityReceived.
  final int? quantityNeeded;
  final String? unit;
  final String? instructions;
  final int quantityReceived;

  InKindItem({
    required this.category,
    required this.description,
    this.quantityNeeded,
    this.unit,
    this.instructions,
    this.quantityReceived = 0,
  });

  int? get quantityRemaining {
    if (quantityNeeded == null) return null;
    final r = quantityNeeded! - quantityReceived;
    return r > 0 ? r : 0;
  }

  factory InKindItem.fromMap(Map<String, dynamic> map) {
    return InKindItem(
      category: map['category'] ?? '',
      description: map['description'] ?? '',
      quantityNeeded: (map['quantityNeeded'] is num) ? (map['quantityNeeded'] as num).toInt() : null,
      unit: map['unit'] as String?,
      instructions: map['instructions'] as String?,
      quantityReceived: (map['quantityReceived'] is num) ? (map['quantityReceived'] as num).toInt() : 0,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'category': category,
      'description': description,
      'quantityNeeded': quantityNeeded,
      'unit': unit,
      'instructions': instructions,
      'quantityReceived': quantityReceived,
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

    return HistoryItem(
      id: doc.id,
      type: type,
      organizer: data['organizer'] ?? '',
      dateTime: (data['timestamp'] as Timestamp?)?.toDate() ?? DateTime.now(),
      refNumber: data['refNumber'] ?? '',
      status: inKindStatus,
      donationMethod: data['donationMethod'],
      amount: (data['amount'] ?? 0).toDouble(),
      itemDescription: data['itemDescription'],
      campaignName: data['campaignName'],
      category: data['category'],
      clarification: data['clarification'],
      isAnonymous: data['isAnonymous'],
      address: data['address'],
      campaignId: data['campaignId'],
      nextChargeDate: data['nextChargeDate'] != null ? (data['nextChargeDate'] as Timestamp).toDate() : null,
      sponsorshipStatus: data['sponsorshipStatus'] ?? (rawType == 'sponsorship' ? 'active' : null),
      pet: data['pet'] != null ? SponsorPet.fromFirestore(data['pet']) : null,
      nextChargeAmount: (data['nextChargeAmount'] ?? 0).toDouble(),
    );
  }
}
