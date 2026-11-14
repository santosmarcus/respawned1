import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:respawnd1/app_theme.dart';
import 'package:respawnd1/core/models/dashboard/dashboard_model.dart';
import 'package:respawnd1/core/models/rescue/animal_record.dart';
import 'package:respawnd1/core/models/rescue/medication.dart';
import 'package:respawnd1/core/repos/auth_service.dart';
import 'package:respawnd1/features/admin/animals/widgets/medication_section.dart';
import 'package:respawnd1/features/admin/rescue/state/rescue_reports_providers.dart';
import 'package:respawnd1/features/admin/animals/widgets/care_updates_section.dart';

/// Home for organization members with the `carer` role. Carers give care and
/// record doses; they don't get the admin shell (cases, records, adoptions,
/// finance). firestore.rules enforces the same split.
class CarerHomeScreen extends ConsumerWidget {
  const CarerHomeScreen({super.key, required this.organizationId});

  final String organizationId;

  Future<void> _signOut(BuildContext context, WidgetRef ref) async {
    final navigator = Navigator.of(context, rootNavigator: true);
    // AuthWrapper swaps this screen out as soon as auth state changes, which
    // disposes `ref`; the container outlives it.
    final container = ProviderScope.containerOf(context, listen: false);
    await authService.value.signOut();
    container.invalidate(currentOrgMembershipProvider);
    container.invalidate(currentOrganizationCapabilitiesProvider);
    navigator.popUntil((route) => route.isFirst);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        title: Text('Care tasks', style: GoogleFonts.tiltWarp(fontSize: 20, color: AppColors.textPrimary)),
        actions: [
          IconButton(
            tooltip: 'Log out',
            icon: const Icon(Icons.logout, color: AppColors.textPrimary),
            onPressed: () => _signOut(context, ref),
          ),
        ],
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance
            .collection('animals')
            .where('organizationId', isEqualTo: organizationId)
            .snapshots(),
        builder: (context, snap) {
          if (snap.hasError) {
            return _message('Could not load animals right now.');
          }
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator(color: AppColors.greenrspwn));
          }
          final animals = snap.data!.docs
              .map(AnimalRecord.fromFirestore)
              .where(isInCare)
              .toList()
            ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
          if (animals.isEmpty) return _message('No animals in care.');

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text('Every animal in care. Record each dose as you give it, and add an update for anything '
                  'staff should know.',
                  style: GoogleFonts.zain(fontSize: 13, color: AppColors.textSecondary)),
              const SizedBox(height: 12),
              for (final a in animals) _AnimalCareCard(animal: a),
            ],
          );
        },
      ),
    );
  }

  Widget _message(String text) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(text,
              textAlign: TextAlign.center,
              style: GoogleFonts.zain(fontSize: 14, color: AppColors.textSecondary)),
        ),
      );
}

/// One animal's care card: its medication orders (when it has any) and the
/// latest care updates.
class _AnimalCareCard extends ConsumerWidget {
  const _AnimalCareCard({required this.animal});

  final AnimalRecord animal;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final plans = ref.watch(medicationPlansProvider(animal.id)).asData?.value ?? const <MedicationPlan>[];
    final hasOrders = plans.any((p) => p.active);

    final notes = [
      if ((animal.health.currentMedications ?? '').trim().isNotEmpty)
        'Medication notes: ${animal.health.currentMedications!.trim()}',
      if (animal.hasSpecialNeeds) 'Special needs recorded — check with an admin before handling.',
    ];

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 6)],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(animal.name.isEmpty ? 'Unnamed animal' : animal.name,
              style: GoogleFonts.tiltWarp(fontSize: 16, color: AppColors.textPrimary)),
          for (final n in notes)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(n, style: GoogleFonts.zain(fontSize: 12, color: AppColors.textSecondary)),
            ),
          if (hasOrders) ...[
            const SizedBox(height: 6),
            MedicationSection(animal: animal),
          ],
          const SizedBox(height: 8),
          CareUpdatesSection(animal: animal, limit: 2),
        ],
      ),
    );
  }
}
