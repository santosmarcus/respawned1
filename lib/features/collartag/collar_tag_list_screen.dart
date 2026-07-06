import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../app_theme.dart';
import 'collar_id_tag_intro.dart';
import 'collar_id_tag_screen.dart';
import 'collar_tag_data_model.dart';
import 'collar_tag_form_screen.dart';


class CollarTagHomeScreen extends StatelessWidget {
  const CollarTagHomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return const CollarIdTagIntroScreen();

    return FutureBuilder<QuerySnapshot<Map<String, dynamic>>>(
      future: FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('collarTags')
          .limit(1)
          .get(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            backgroundColor: AppColors.background,
            body: Center(
              child: CircularProgressIndicator(color: AppColors.textPrimary),
            ),
          );
        }

        // If the check fails for any reason, fall back to the intro screen
        // rather than blocking the user from creating their first tag.
        final hasTags = snapshot.data?.docs.isNotEmpty ?? false;
        return hasTags
            ? const CollarTagsListScreen()
            : const CollarIdTagIntroScreen();
      },
    );
  }
}

class CollarTagsListScreen extends StatefulWidget {
  const CollarTagsListScreen({super.key});

  @override
  State<CollarTagsListScreen> createState() => _CollarTagsListScreenState();
}

class _CollarTagsListScreenState extends State<CollarTagsListScreen> {
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _sub;
  List<CollarTagData> _tags = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _listen();
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  void _listen() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      setState(() => _loading = false);
      return;
    }

    _sub = FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('collarTags')
        .snapshots()
        .listen(
          (snap) {
        final tags = <CollarTagData>[];
        for (final d in snap.docs) {
          try {
            tags.add(CollarTagData.fromFirestore(d.data(), d.id));
          } catch (_) {
            // skip malformed doc
          }
        }
        tags.sort((a, b) {
          final at = a.createdAt, bt = b.createdAt;
          if (at == null && bt == null) return 0;
          if (at == null) return 1;
          if (bt == null) return -1;
          return bt.compareTo(at);
        });

        if (!mounted) return;
        setState(() {
          _tags = tags;
          _loading = false;
        });
      },
      onError: (_) {
        if (mounted) setState(() => _loading = false);
      },
    );
  }

  void _createNew() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const CollarTagFormScreen()),
    );
  }

  void _openTag(CollarTagData tag) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CollarIdTagCardScreen(tagData: tag),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.chevron_left,
              color: AppColors.textPrimary, size: 28),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Create Pet Collar\nTags',
              textAlign: TextAlign.center,
              style: GoogleFonts.tiltWarp(
                fontSize: 26,
                fontWeight: FontWeight.bold,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'Tags',
              style: GoogleFonts.tiltWarp(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: _loading
                  ? const Center(
                child: CircularProgressIndicator(
                    color: AppColors.textPrimary),
              )
                  : _tags.isEmpty
                  ? Center(
                child: Text(
                  'No collar tags yet.',
                  style: GoogleFonts.zain(
                      fontSize: 14, color: AppColors.textSecondary),
                ),
              )
                  : ListView.separated(
                itemCount: _tags.length,
                separatorBuilder: (_, __) => const Divider(
                    height: 24, color: AppColors.slaterspwn),
                itemBuilder: (_, i) => _TagRow(
                  tag: _tags[i],
                  onTap: () => _openTag(_tags[i]),
                ),
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _createNew,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.yellowrspwn,
                  foregroundColor: AppColors.textPrimary,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(30)),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  elevation: 0,
                ),
                child: Text(
                  'Create Now!',
                  style: GoogleFonts.tiltWarp(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textPrimary),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TagRow extends StatelessWidget {
  final CollarTagData tag;
  final VoidCallback onTap;
  const _TagRow({required this.tag, required this.onTap});

  String get _statusText =>
      tag.qrEnabled ? 'Ready to view' : 'Order is being processed';

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: _thumb(),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  tag.name.isNotEmpty ? tag.name : 'Unnamed pet',
                  style: GoogleFonts.tiltWarp(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Text(
                  _statusText,
                  style: GoogleFonts.zain(
                      fontSize: 13, color: AppColors.textPrimary),
                ),
              ],
            ),
          ),
          const Icon(Icons.chevron_right,
              color: AppColors.textPrimary, size: 20),
        ],
      ),
    );
  }

  Widget _thumb() {
    if (tag.petImageUrl != null && tag.petImageUrl!.isNotEmpty) {
      return Image.network(
        tag.petImageUrl!,
        width: 64,
        height: 64,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _placeholder(),
      );
    }
    return _placeholder();
  }

  Widget _placeholder() => Container(
    width: 64,
    height: 64,
    color: AppColors.tearspwn,
    child: const Icon(Icons.pets, color: AppColors.textPrimary),
  );
}