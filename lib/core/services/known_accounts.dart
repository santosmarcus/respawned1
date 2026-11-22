import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// How an account signs in, which decides how "Switch account" brings it
/// back: email accounts re-enter their password, Google accounts pick
/// themselves in Google's account chooser, phone accounts get an SMS code.
enum KnownAccountMethod { password, google, phone }

/// An account that has signed in on this device. Only what the Switch
/// account list shows (no passwords or tokens: Firebase keeps one signed-in
/// account at a time, so switching signs in again).
class KnownAccount {
  const KnownAccount({
    required this.uid,
    required this.name,
    required this.method,
    this.email = '',
    this.phone = '',
    this.photoUrl,
    this.lastUsedAt,
  });

  final String uid;
  final String name;
  final KnownAccountMethod method;
  final String email;
  final String phone;
  final String? photoUrl;
  final DateTime? lastUsedAt;

  /// The email or phone shown under the name.
  String get contact => email.isNotEmpty ? email : phone;

  Map<String, Object?> toJson() => {
        'uid': uid,
        'name': name,
        'method': method.name,
        'email': email,
        'phone': phone,
        'photoUrl': photoUrl,
        'lastUsedAt': lastUsedAt?.millisecondsSinceEpoch,
      };

  static KnownAccount? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final uid = raw['uid'];
    if (uid is! String || uid.isEmpty) return null;
    final method = KnownAccountMethod.values.where((m) => m.name == raw['method']).firstOrNull;
    if (method == null) return null;
    final used = raw['lastUsedAt'];
    return KnownAccount(
      uid: uid,
      name: (raw['name'] as String?) ?? '',
      method: method,
      email: (raw['email'] as String?) ?? '',
      phone: (raw['phone'] as String?) ?? '',
      photoUrl: raw['photoUrl'] as String?,
      lastUsedAt: used is int ? DateTime.fromMillisecondsSinceEpoch(used) : null,
    );
  }
}

/// The accounts signed in on this device, most recent first (local only).
class KnownAccounts {
  KnownAccounts._();

  static const _key = 'knownAccounts.v1';
  static const _max = 5;

  /// Set by "Switch account" just before signing out; the login screen
  /// reads it once to sign this account back in.
  static final ValueNotifier<KnownAccount?> pendingSwitch = ValueNotifier(null);

  static Future<List<KnownAccount>> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key);
      if (raw == null) return const [];
      final list = jsonDecode(raw);
      if (list is! List) return const [];
      return list.map(KnownAccount.fromJson).whereType<KnownAccount>().toList();
    } catch (e) {
      debugPrint('KnownAccounts.load failed: $e');
      return const [];
    }
  }

  static Future<void> _save(List<KnownAccount> accounts) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(accounts.map((a) => a.toJson()).toList()));
  }

  static KnownAccountMethod _methodOf(User user) {
    final providers = user.providerData.map((p) => p.providerId).toSet();
    if (providers.contains('password')) return KnownAccountMethod.password;
    if (providers.contains('google.com')) return KnownAccountMethod.google;
    return KnownAccountMethod.phone;
  }

  /// Records (or refreshes) the signed-in [user] at the top of the list.
  static Future<void> remember(User user, Map<String, dynamic>? profile) async {
    try {
      final first = (profile?['firstName'] as String?)?.trim() ?? '';
      final last = (profile?['lastName'] as String?)?.trim() ?? '';
      final full = '$first $last'.trim();
      final photo = (profile?['photoUrl'] as String?)?.trim();
      final account = KnownAccount(
        uid: user.uid,
        name: full.isNotEmpty ? full : (user.displayName ?? user.email ?? user.phoneNumber ?? 'Account'),
        method: _methodOf(user),
        email: user.email ?? '',
        phone: user.phoneNumber ?? '',
        photoUrl: (photo != null && photo.startsWith('http')) ? photo : user.photoURL,
        lastUsedAt: DateTime.now(),
      );
      final others = (await load()).where((a) => a.uid != user.uid);
      await _save([account, ...others].take(_max).toList());
    } catch (e) {
      debugPrint('KnownAccounts.remember failed: $e');
    }
  }

  static Future<void> forget(String uid) async {
    final rest = (await load()).where((a) => a.uid != uid).toList();
    await _save(rest);
  }
}
