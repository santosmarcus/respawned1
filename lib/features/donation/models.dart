import 'package:flutter/material.dart';

enum CardType { visa, mastercard, other }

extension CardTypeExtension on CardType {
  String get name {
    switch (this) {
      case CardType.visa:
        return 'Visa';
      case CardType.mastercard:
        return 'Mastercard';
      case CardType.other:
        return 'Other';
    }
  }
}

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

  DonationItem({required this.description, required this.amount});
}

class Organization {
  final String id;
  final String name;
  final String location;
  final String website;
  final String imageUrl;
  final bool hasFacebook;
  final bool hasInstagram;
  final bool hasSpotify;
  final bool hasEmail;
  bool isFavorite;

  Organization({
    required this.id,
    required this.name,
    required this.location,
    required this.website,
    this.imageUrl =
        'https://www.gstatic.com/flutter-onestack-prototype/genui/example_1.jpg',
    this.hasFacebook = true,
    this.hasInstagram = true,
    this.hasSpotify = true,
    this.hasEmail = true,
    this.isFavorite = false,
  });

  Organization copyWith({bool? isFavorite}) {
    return Organization(
      id: id,
      name: name,
      location: location,
      website: website,
      imageUrl: imageUrl,
      hasFacebook: hasFacebook,
      hasInstagram: hasInstagram,
      hasSpotify: hasSpotify,
      hasEmail: hasEmail,
      isFavorite: isFavorite ?? this.isFavorite,
    );
  }
}

class Fundraiser {
  final String id;
  final String name;
  final String description;
  final String imageUrl;
  final double targetAmount;
  double currentAmount;
  final bool hasFacebook;
  final bool hasInstagram;
  final bool hasSpotify;
  final bool hasEmail;
  final int daysLeft;
  bool isFavorite;

  Fundraiser({
    required this.id,
    required this.name,
    required this.description,
    required this.targetAmount,
    required this.daysLeft,
    this.currentAmount = 0.0,
    this.imageUrl =
        'https://www.gstatic.com/flutter-onestack-prototype/genui/example_1.jpg',
    this.hasFacebook = true,
    this.hasInstagram = true,
    this.hasSpotify = true,
    this.hasEmail = true,
    this.isFavorite = false,
  });

  Fundraiser copyWith({
    bool? isFavorite,
    double? currentAmount,
    int? daysLeft,
  }) {
    return Fundraiser(
      id: id,
      name: name,
      description: description,
      targetAmount: targetAmount,
      currentAmount: currentAmount ?? this.currentAmount,
      imageUrl: imageUrl,
      hasFacebook: hasFacebook,
      hasInstagram: hasInstagram,
      hasSpotify: hasSpotify,
      hasEmail: hasEmail,
      isFavorite: isFavorite ?? this.isFavorite,
      daysLeft: daysLeft ?? this.daysLeft,
    );
  }
}
