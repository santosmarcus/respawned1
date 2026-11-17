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

  Future<void> _attach() async {
    final picked = await pickImageWithSource(context, ImagePicker(), imageQuality: 85);
    if (picked == null || !mounted) return;
    setState(() => _busy = true);
    try {
      final ref0 = FirebaseStorage.instance
          .ref('adoptions/${widget.app.id}/signed_agreement_${DateTime.now().millisecondsSinceEpoch}.jpg');
      await ref0.putFile(File(picked.path));
      await ref.read(adoptionApplicationRepositoryProvider).attachSignedAgreement(
        applicationId: widget.app.id,
        url: await ref0.getDownloadURL(),
        actorName: widget.actorName,
      );
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(appSnackBar('Signed agreement attached.'));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(appSnackBar('Could not attach: $e', kind: AppMessageKind.error));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
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
            child: Text(url == null ? 'Attach' : 'Replace'),
          ),
        ],
      ),
    );
  }
}
