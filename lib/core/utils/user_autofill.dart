import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/widgets.dart';

/// The signed-in user's own details, for pre-filling forms that ask for
/// them again (name, email, mobile number, address), so nobody retypes
/// what they already gave the app.
///
/// Name and phone come from `users/{uid}` (set at sign-up), email from the
/// sign-in account, and address from the last address they entered in a
/// form ([rememberAddress]).
class UserAutofill {
  final String firstName;
  final String lastName;
  final String email;
  final String phone;
  final String address;

  const UserAutofill({
    this.firstName = '',
    this.lastName = '',
    this.email = '',
    this.phone = '',
    this.address = '',
  });

  String get fullName => '$firstName $lastName'.trim();

  /// The current user's details, or null when signed out or unreadable.
  static Future<UserAutofill?> load() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return null;
    try {
      final doc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
      final d = doc.data() ?? const <String, dynamic>{};
      String s(Object? v) => v == null ? '' : v.toString().trim();
      var first = s(d['firstName']);
      var last = s(d['lastName']);
      if (first.isEmpty && last.isEmpty) {
        final parts = s(d['name'] ?? user.displayName).split(RegExp(r'\s+'));
        first = parts.isEmpty ? '' : parts.first;
        last = parts.length > 1 ? parts.sublist(1).join(' ') : '';
      }
      return UserAutofill(
        firstName: first,
        lastName: last,
        email: s(user.email).isNotEmpty ? s(user.email) : s(d['email']),
        phone: s(d['phone'] ?? d['phoneNumber']),
        address: s(d['address'] ?? d['homeAddress']),
      );
    } catch (_) {
      return null;
    }
  }

  /// Saves [address] on the user's profile so later forms can fill it in.
  static Future<void> rememberAddress(String address) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    final value = address.trim();
    if (uid == null || value.isEmpty) return;
    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .set({'address': value}, SetOptions(merge: true));
    } catch (_) {
      // Best effort: the form itself was already submitted.
    }
  }
}

/// Puts [value] into [controller] only when the field is still empty, so
/// nothing the user already typed (or a saved draft) is overwritten.
void fillIfEmpty(TextEditingController controller, String value) {
  if (controller.text.trim().isEmpty && value.trim().isNotEmpty) {
    controller.text = value.trim();
  }
}
