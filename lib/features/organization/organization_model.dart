import 'package:cloud_firestore/cloud_firestore.dart';

class Organization {
  final String id;
  final String name;
  final String? avatarUrl;
  final String? coverImageUrl;
  final String location;
  final int rescuesCount;
  final int adopteesCount;
  final int eventsCount;
  final String? phone;
  final String? facebookUrl;
  final String? email;
  final String? mapUrl;
  final String description;
  final String? bookVisitUrl;
  final double averageRating;
  final int reviewCount;
  final bool favorited;

  Organization({
    required this.id,
    required this.name,
    this.avatarUrl,
    this.coverImageUrl,
    this.location = '',
    this.rescuesCount = 0,
    this.adopteesCount = 0,
    this.eventsCount = 0,
    this.phone,
    this.facebookUrl,
    this.email,
    this.mapUrl,
    this.description = '',
    this.bookVisitUrl,
    this.averageRating = 0,
    this.reviewCount = 0,
    this.favorited = false,
  });

  factory Organization.fromFirestore(
      DocumentSnapshot<Map<String, dynamic>> doc, {
        bool favorited = false,
      }) {
    final data = doc.data() ?? <String, dynamic>{};
    return Organization(
      id: doc.id,
      name: data['name'] as String? ?? '',
      avatarUrl: data['avatarUrl'] as String?,
      coverImageUrl: data['coverImageUrl'] as String?,
      location: data['location'] as String? ?? '',
      rescuesCount: (data['rescuesCount'] as num?)?.toInt() ?? 0,
      adopteesCount: (data['adopteesCount'] as num?)?.toInt() ?? 0,
      eventsCount: (data['eventsCount'] as num?)?.toInt() ?? 0,
      phone: data['phone'] as String?,
      facebookUrl: data['facebookUrl'] as String?,
      email: data['email'] as String?,
      mapUrl: data['mapUrl'] as String?,
      description: data['description'] as String? ?? '',
      bookVisitUrl: data['bookVisitUrl'] as String?,
      averageRating: (data['averageRating'] as num?)?.toDouble() ?? 0,
      reviewCount: (data['reviewCount'] as num?)?.toInt() ?? 0,
      favorited: favorited,
    );
  }

  Organization copyWith({bool? favorited}) {
    return Organization(
      id: id,
      name: name,
      avatarUrl: avatarUrl,
      coverImageUrl: coverImageUrl,
      location: location,
      rescuesCount: rescuesCount,
      adopteesCount: adopteesCount,
      eventsCount: eventsCount,
      phone: phone,
      facebookUrl: facebookUrl,
      email: email,
      mapUrl: mapUrl,
      description: description,
      bookVisitUrl: bookVisitUrl,
      averageRating: averageRating,
      reviewCount: reviewCount,
      favorited: favorited ?? this.favorited,
    );
  }
}