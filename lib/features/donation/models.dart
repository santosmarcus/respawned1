import 'package:flutter/material.dart';

enum CardType { visa, mastercard, other }

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

  DonationReviewParams({
    required this.fundraiserId,
    required this.organizationName,
    required this.donationMethod,
    required this.item,
    required this.isAnonymous,
    this.pet,
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
          pet?.id == other.pet?.id;

  @override
  int get hashCode =>
      fundraiserId.hashCode ^
      organizationName.hashCode ^
      donationMethod.hashCode ^
      item.amount.hashCode ^
      item.description.hashCode ^
      isAnonymous.hashCode ^
      (pet?.id).hashCode;
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
