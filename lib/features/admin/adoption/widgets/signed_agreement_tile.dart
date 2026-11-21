import 'dart:async';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:respawnd1/app_theme.dart';
import 'package:respawnd1/core/models/adoption/adoption_application.dart';
import 'package:respawnd1/core/utils/app_date_format.dart';
import 'package:respawnd1/core/widgets/app_messages.dart';
import 'package:respawnd1/core/widgets/image_source_sheet.dart';
import 'package:respawnd1/features/admin/adoption/state/adoption_providers.dart';
import 'package:respawnd1/features/admin/rescue/widgets/section_card.dart';

/// Thrown by [uploadSignedAgreement] when no bytes went up for a while
/// (offline or a stuck connection). The upload is cancelled.
class AgreementUploadStalled implements Exception {
  const AgreementUploadStalled();
  @override
  String toString() => 'The upload stopped moving. Check your connection and try again.';
}

/// Picks a photo of the signed agreement, sized for reading rather than at
/// full camera resolution (a phone photo can be several MB).
Future<XFile?> pickSignedAgreementPhoto(BuildContext context) =>
    pickImageWithSource(context, ImagePicker(), imageQuality: 80, maxWidth: 1800);

/// Uploads the agreement photo for [applicationId] and returns its download
/// URL. [onProgress] gets 0–1. Instead of a fixed time limit (a slow but
/// moving upload is fine), it gives up when no bytes move for [stallAfter].
Future<String> uploadSignedAgreement(
  String applicationId,
  XFile file, {
  void Function(double fraction)? onProgress,
  Duration stallAfter = const Duration(seconds: 30),
}) async {
  final storageRef = FirebaseStorage.instance
      .ref('adoptions/$applicationId/signed_agreement_${DateTime.now().millisecondsSinceEpoch}.jpg');
  final task = storageRef.putFile(File(file.path), SettableMetadata(contentType: 'image/jpeg'));
  var lastBytes = -1;
  var lastMove = DateTime.now();
  var stalled = false;
  final sub = task.snapshotEvents.listen((s) {
    if (s.bytesTransferred != lastBytes) {
      lastBytes = s.bytesTransferred;
      lastMove = DateTime.now();
    }
    if (s.totalBytes > 0) onProgress?.call(s.bytesTransferred / s.totalBytes);
  }, onError: (_) {});
  final watchdog = Timer.periodic(const Duration(seconds: 5), (_) {
    if (DateTime.now().difference(lastMove) > stallAfter) {
      stalled = true;
      task.cancel();
    }
  });
  try {
    await task;
  } on FirebaseException catch (e) {
    if (stalled || e.code == 'canceled') throw const AgreementUploadStalled();
    rethrow;
  } finally {
    watchdog.cancel();
    await sub.cancel();
  }
  return storageRef.getDownloadURL();
}

/// Message for a failed agreement upload, with the Storage error code so a
/// permissions problem is told apart from a connection one.
String agreementUploadError(Object e) {
  if (e is AgreementUploadStalled) return e.toString();
  if (e is FirebaseException) {
    return switch (e.code) {
      'unauthorized' => "You don't have permission to upload files for this adoption.",
      'retry-limit-exceeded' => 'The upload kept failing. Check your connection and try again.',
      _ => 'Could not upload the agreement (${e.code}).',
    };
  }
  return 'Could not attach: $e';
}

/// Adoption gap 6 on Post-Adoption Details: the photo or scan of the
/// agreement both parties signed at release, kept with the adoption. Staff
/// can view it, or attach it if the release was done without it.
class SignedAgreementTile extends ConsumerStatefulWidget {
  const SignedAgreementTile({super.key, required this.app, required this.actorName});
  final AdoptionApplication app;
  final String actorName;

  @override
  ConsumerState<SignedAgreementTile> createState() => _SignedAgreementTileState();
}

class _SignedAgreementTileState extends ConsumerState<SignedAgreementTile> {
  bool _busy = false;
  double? _progress;

  Future<void> _attach() async {
    final picked = await pickSignedAgreementPhoto(context);
    if (picked == null || !mounted) return;
    setState(() {
      _busy = true;
      _progress = 0;
    });
    try {
      final url = await uploadSignedAgreement(widget.app.id, picked,
          onProgress: (p) => mounted ? setState(() => _progress = p) : null);
      await ref.read(adoptionApplicationRepositoryProvider).attachSignedAgreement(
        applicationId: widget.app.id,
        url: url,
        actorName: widget.actorName,
      );
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(appSnackBar('Signed agreement attached.'));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(appSnackBar(agreementUploadError(e), kind: AppMessageKind.error));
      }
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _progress = null;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final url = widget.app.raw['signedAgreementUrl'] as String?;
    final at = widget.app.raw['signedAgreementAt'];
    final when = at is Timestamp ? at.toDate() : null;
    return SectionCard(
      title: 'Signed agreement',
      child: Row(
        children: [
          Icon(url == null ? Icons.warning_amber : Icons.check_circle,
              color: url == null ? AppColors.warning : AppColors.success),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              url == null
                  ? 'No signed agreement on file.'
                  : 'On file${when == null ? '' : ' since ${formatDate(when)}'}'
                  '${widget.app.raw['signedAgreementBy'] == null ? '' : ' (${widget.app.raw['signedAgreementBy']})'}.',
              style: GoogleFonts.zain(fontSize: 13, color: AppColors.textPrimary),
            ),
          ),
          if (url != null)
            TextButton(
              onPressed: () => launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication),
              child: const Text('View'),
            ),
          TextButton(
            onPressed: _busy ? null : _attach,
            child: Text(_progress != null
                ? 'Uploading ${(_progress! * 100).round()}%'
                : (url == null ? 'Attach' : 'Replace')),
          ),
        ],
      ),
    );
  }
}
