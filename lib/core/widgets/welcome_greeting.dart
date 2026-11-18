import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The signed-in user's first name from `users/{uid}.firstName`, falling
/// back to the first word of the auth display name (Google sign-in). Null
/// while loading or when neither is set.
final currentUserFirstNameProvider = StreamProvider.autoDispose<String?>((ref) {
  final user = FirebaseAuth.instance.currentUser;
  if (user == null) return Stream.value(null);
  String? fallback() {
    final display = user.displayName?.trim() ?? '';
    return display.isEmpty ? null : display.split(RegExp(r'\s+')).first;
  }

  return FirebaseFirestore.instance.collection('users').doc(user.uid).snapshots().map((snap) {
    final first = (snap.data()?['firstName'] as String?)?.trim() ?? '';
    return first.isNotEmpty ? first : fallback();
  });
});

/// "Welcome, {first name}" — just "Welcome" until the name is known, never
/// "Welcome, !" for an account without a name yet.
class WelcomeGreeting extends ConsumerWidget {
  const WelcomeGreeting({super.key, this.style, this.exclaim = false});

  final TextStyle? style;
  final bool exclaim;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final name = ref.watch(currentUserFirstNameProvider).value;
    final mark = exclaim ? '!' : '';
    return Text(
      name == null ? 'Welcome$mark' : 'Welcome, $name$mark',
      style: style,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }
}
