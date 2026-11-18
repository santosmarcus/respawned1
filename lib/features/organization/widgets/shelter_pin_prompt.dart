import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:respawnd1/app_theme.dart';
import 'package:respawnd1/features/organization/shelter_location_picker_page.dart';

/// Whether [organizationId] has a saved shelter pin (shelterLat/shelterLng
/// on organizations/{id}). The transporter's shelter leg needs it: there is
/// no default shelter (transit_rules.dart). Null while loading or with no
/// organization.
final shelterPinSetProvider = StreamProvider.autoDispose.family<bool?, String>((ref, organizationId) {
  if (organizationId.isEmpty) return Stream.value(null);
  return FirebaseFirestore.instance.collection('organizations').doc(organizationId).snapshots().map((d) {
    final data = d.data();
    if (data == null) return null;
    return data['shelterLat'] is num && data['shelterLng'] is num;
  });
});

/// Asks for the organization's shelter location when it isn't set. Admins
/// get a button to set it; everyone else is told to ask one. [message]
/// overrides the default explanation (e.g. on a case that is waiting).
class ShelterPinPrompt extends ConsumerWidget {
  final String organizationId;
  final bool canSet;
  final String? message;
  const ShelterPinPrompt({super.key, required this.organizationId, required this.canSet, this.message});

  Future<void> _openPicker(BuildContext context) async {
    // The prompt's own stream has this doc cached; read the cache first so
    // the picker opens without a round trip.
    final ref = FirebaseFirestore.instance.collection('organizations').doc(organizationId);
    DocumentSnapshot<Map<String, dynamic>> doc;
    try {
      doc = await ref.get(const GetOptions(source: Source.cache));
    } catch (_) {
      doc = await ref.get();
    }
    final d = doc.data() ?? const <String, dynamic>{};
    if (!context.mounted) return;
    await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => ShelterLocationPickerPage(
          organizationId: organizationId,
          initialName: d['shelterName'] as String?,
          initialAddress: d['shelterAddress'] as String?,
          initialPlaceId: d['shelterPlaceId'] as String?,
          initialLat: (d['shelterLat'] as num?)?.toDouble(),
          initialLng: (d['shelterLng'] as num?)?.toDouble(),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isSet = ref.watch(shelterPinSetProvider(organizationId)).asData?.value;
    if (isSet != false) return const SizedBox.shrink();
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.warning.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.warning.withValues(alpha: 0.6)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.location_off, color: AppColors.warning, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text('Shelter location not set',
                    style: GoogleFonts.zain(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            message ??
                'Transporters can only take animals to your shelter once its exact location is pinned. '
                    'Arrival is checked within 150 m of the pin.',
            style: GoogleFonts.zain(fontSize: 13, color: AppColors.textPrimary),
          ),
          const SizedBox(height: 8),
          if (canSet)
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton(
                style: FilledButton.styleFrom(backgroundColor: AppColors.textPrimary),
                onPressed: () => _openPicker(context),
                child: Text('Set shelter location',
                    style: GoogleFonts.zain(fontWeight: FontWeight.w700, color: AppColors.background)),
              ),
            )
          else
            Text('Ask an organization admin to set it in Organization Profile.',
                style: GoogleFonts.zain(fontSize: 12, color: AppColors.textSecondary)),
        ],
      ),
    );
  }
}
