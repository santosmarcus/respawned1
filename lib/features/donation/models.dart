import 'package:flutter/material.dart';

enum CardType { visa, mastercard, other }

enum HistoryType { donation, inKindDonation, sponsorship }

enum InKindStatus { complete, inProgress, cancelled }

class CreditCard {
  final CardType cardType;
  final String cardNumberLastFour;
  final String cardHolderName;
  final String expiryDate;
  final Color backgroundColor;

  CreditCard({
    required this.cardType,
    required this.cardNumberLastFour,
    required this.cardHolderName,
    required this.expiryDate,
    required this.backgroundColor,
  });
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
  final bool isSponsorship;

  DonationReviewParams({
    required this.fundraiserId,
    required this.organizationName,
    required this.donationMethod,
    required this.item,
    required this.isAnonymous,
    this.pet,
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
  final int id;
  final String title;
  final int target;
  final int collected;
  final int percentage;
  final int dateleft;
  final String organizer;
  final String date;
  final String time;
  final String description;
  final int numdonated;
  final String address;
  bool favorited;
  bool donated;

  DonationListing({
    required this.id,
    required this.title,
    required this.target,
    required this.collected,
    required this.percentage,
    required this.dateleft,
    required this.organizer,
    required this.date,
    required this.time,
    required this.description,
    required this.numdonated,
    required this.address,
    this.favorited = false,
    this.donated = false,
  });
}

class SponsorPet {
  final int id;
  final String name;
  final String breed;
  final int age;
  final String description;
  final List<String> tags;
  bool favorited;

  SponsorPet({
    required this.id,
    required this.name,
    required this.breed,
    required this.age,
    required this.description,
    required this.tags,
    this.favorited = false,
  });
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

  // In-kind specific
  final String? category;
  final String? clarification;
  final bool? isAnonymous;
  final String? address;

  // Sponsorship specific
  final DateTime? nextChargeDate;
  final bool? isCancelled;
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
    this.category,
    this.clarification,
    this.isAnonymous,
    this.address,
    this.nextChargeDate,
    this.isCancelled,
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
    String? category,
    String? clarification,
    bool? isAnonymous,
    String? address,
    DateTime? nextChargeDate,
    bool? isCancelled,
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
      category: category ?? this.category,
      clarification: clarification ?? this.clarification,
      isAnonymous: isAnonymous ?? this.isAnonymous,
      address: address ?? this.address,
      nextChargeDate: nextChargeDate ?? this.nextChargeDate,
      isCancelled: isCancelled ?? this.isCancelled,
      pet: pet ?? this.pet,
      nextChargeAmount: nextChargeAmount ?? this.nextChargeAmount,
    );
  }
}
