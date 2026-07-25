import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:respawnd1/app_theme.dart';
import 'package:respawnd1/core/models/rescue/expense.dart';
import 'package:respawnd1/core/models/rescue/rescue_case.dart';
import 'package:respawnd1/core/models/rescue/treatment_log_entry.dart';
import 'package:respawnd1/core/utils/currency.dart';
import 'package:respawnd1/features/admin/animals/state/animal_records_providers.dart';
import 'package:respawnd1/features/admin/rescue/expenses/add_edit_expense_sheet.dart';
import 'package:respawnd1/features/admin/rescue/expenses/create_fundraiser_draft_page.dart';
import 'package:respawnd1/features/admin/rescue/expenses/expense_list_page.dart';
import 'package:respawnd1/features/admin/rescue/intake_detail_page.dart';
import 'package:respawnd1/features/admin/rescue/state/rescue_reports_providers.dart';
import 'package:respawnd1/features/admin/rescue/widgets/case_animal_selector.dart';
import 'package:respawnd1/features/admin/rescue/widgets/close_case_sheet.dart';
import 'package:respawnd1/features/admin/rescue/widgets/confirm_action_dialog.dart';
import 'package:respawnd1/features/admin/rescue/widgets/release_animal_sheet.dart';
import 'package:respawnd1/features/admin/rescue/widgets/transfer_animal_sheet.dart';
import 'package:respawnd1/features/admin/rescue/widgets/treatment_log_widgets.dart';

const List<String> _conditions = ['Critical', 'Stable', 'Recovering', 'Ready for Discharge'];
const List<String> _causesOfDeath = [
  'Infection',
  'Trauma/Injury',
  'Disease',
  'Treatment Complications',
  'Malnutrition',
  'Other',
];

const _kNextStepIntake = 'Intake';
const _kNextStepTransfer = 'Transfer';
const _kNextStepRelease = 'Release';

class TreatmentDetailPage extends ConsumerStatefulWidget {
  final String caseId;
  final Map<String, dynamic> data;
  const TreatmentDetailPage({super.key, required this.caseId, required this.data});

  @override
  ConsumerState<TreatmentDetailPage> createState() => _TreatmentDetailPageState();
}

class _TreatmentDetailPageState extends ConsumerState<TreatmentDetailPage> {
  bool _showAllLogs = false;
  bool _showUpdateForm = false;
  bool _isSaving = false;
  bool _isActingOnNextStep = false;
  bool _closingCase = false;

  /// Shared by Treatment Logs and Cost Tracking (spec §1) — both sections
  /// live in this one page/State, so a single field naturally preserves the
  /// selection when scrolling between them. Null = All Animals (default).
  /// Keyed by the case's `animals[]` list index — see CaseAnimalOption's
  /// doc comment for why that's the only stable identifier available.
  int? _selectedAnimalIndex;

  /// "Applies to" selection for the update form currently being filled in
  /// — separate from [_selectedAnimalIndex] (the page-level filter) since
  /// the admin can still choose "All Animals" for a log while viewing one
  /// animal's filtered timeline, or vice versa. Empty set = All Animals.
  Set<int> _updateAnimalIndexes = {};

  String get _actorUid => FirebaseAuth.instance.currentUser?.uid ?? '';
  String get _actorName {
    final n = FirebaseAuth.instance.currentUser?.displayName;
    return (n != null && n.isNotEmpty) ? n : 'Admin Staff';
  }

  /// General Close Case (spec §2) — separate from [_closeDeceasedCase]
  /// below, which stays exactly as-is for its own specific
  /// deceased-with-financial-summary flow. This is for every other
  /// exception reason while a case is still in Treatment.
  Future<void> _closeCase(RescueCase c) async {
    if (_closingCase) return;
    final result = await showCloseCaseSheet(context, rescueCase: c);
    if (result == null || !mounted) return;
    setState(() => _closingCase = true);
    try {
      await ref.read(rescueCaseRepositoryProvider).closeCase(
            caseId: c.id,
            reason: result.reason,
            details: result.details,
            actorUid: _actorUid,
            actorName: _actorName,
            lastKnownLocation: result.lastKnownLocation,
            clinicUnavailableDetails: result.clinicUnavailableDetails,
          );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Case closed.')));
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not close case: $e'), backgroundColor: Colors.redAccent));
      }
    } finally {
      if (mounted) setState(() => _closingCase = false);
    }
  }

  // Update form state
  TreatmentUpdateType? _selectedType;
  // Date only, no time-of-day — defaults to today whenever the form opens
  // (see _resetFormToDefaults). createdAt (server timestamp) is the
  // separate audit/order concept, stamped by the repository itself.
  DateTime? _treatmentDate;
  final _notesController = TextEditingController();
  String? _selectedCondition;

  final _medicationNameController = TextEditingController();
  final _medicationDoseController = TextEditingController();
  final _procedureController = TextEditingController();
  final _vaccineNameController = TextEditingController();
  final _vaccineDoseController = TextEditingController();
  DateTime? _nextVaccineSchedule;
  final _dischargeNotesController = TextEditingController();
  String? _finalCondition;
  final _postTreatmentInstructionsController = TextEditingController();
  String? _selectedCauseOfDeath;

  // Image selection/upload state for the current update.
  final _picker = ImagePicker();
  final List<XFile> _pickedMedia = [];
  bool _isUploadingMedia = false;
  String? _mediaError;

  // Post-treatment disposition
  String? _selectedNextStep;

  @override
  void initState() {
    super.initState();
    _treatmentDate = _todayDateOnly();
  }

  static DateTime _todayDateOnly() {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day);
  }

  @override
  void dispose() {
    _notesController.dispose();
    _medicationNameController.dispose();
    _medicationDoseController.dispose();
    _procedureController.dispose();
    _vaccineNameController.dispose();
    _vaccineDoseController.dispose();
    _dischargeNotesController.dispose();
    _postTreatmentInstructionsController.dispose();
    super.dispose();
  }

  bool get _isDeathReport => _selectedType == TreatmentUpdateType.deathReport;
  bool get _isDischarge => _selectedType == TreatmentUpdateType.discharge;

  bool _canSubmit() {
    if (_selectedType == null || _treatmentDate == null) return false;
    if (_isDeathReport) return _selectedCauseOfDeath != null;
    if (_isDischarge) {
      return _finalCondition != null && _dischargeNotesController.text.trim().isNotEmpty;
    }
    return _selectedCondition != null && _notesController.text.trim().isNotEmpty;
  }

  Future<void> _pickFromGallery() async {
    final files = await _picker.pickMultiImage(imageQuality: 80);
    if (files.isNotEmpty && mounted) {
      setState(() {
        _pickedMedia.addAll(files);
        _mediaError = null;
      });
    }
  }

  Future<void> _pickFromCamera() async {
    final file = await _picker.pickImage(source: ImageSource.camera, imageQuality: 80);
    if (file != null && mounted) {
      setState(() {
        _pickedMedia.add(file);
        _mediaError = null;
      });
    }
  }

  void _removeMedia(int index) => setState(() => _pickedMedia.removeAt(index));

  /// Uploads to `cases/{caseId}/treatmentUpdates/{logId}/{index}.{ext}` —
  /// same FirebaseStorage.instance.ref(path)/putFile/getDownloadURL
  /// convention already used by collar_tag_form_screen.dart's own image
  /// upload, just parameterized by this update's own path. Rethrows on
  /// failure (unlike that page's silent-null pattern) so _addUpdate can
  /// stop before ever creating a misleading "successful" log entry, and can
  /// keep the picked images in the form for Retry.
  Future<(String url, String path)> _uploadMedia(XFile file, String storagePath) async {
    final ref = FirebaseStorage.instance.ref(storagePath);
    await ref.putFile(File(file.path));
    final url = await ref.getDownloadURL();
    return (url, storagePath);
  }

  Future<void> _addUpdate() async {
    if (_isSaving || !_canSubmit()) return;
    setState(() {
      _isSaving = true;
      _mediaError = null;
    });

    final repo = ref.read(rescueCaseRepositoryProvider);
    final logId = repo.newTreatmentLogId(widget.caseId);

    final mediaUrls = <String>[];
    final mediaTypes = <String>[];
    final storagePaths = <String>[];

    if (_pickedMedia.isNotEmpty) {
      setState(() => _isUploadingMedia = true);
      try {
        for (var i = 0; i < _pickedMedia.length; i++) {
          final file = _pickedMedia[i];
          final ext = file.path.contains('.') ? file.path.split('.').last : 'jpg';
          final storagePath = 'cases/${widget.caseId}/treatmentUpdates/$logId/$i.$ext';
          final (url, path) = await _uploadMedia(file, storagePath);
          mediaUrls.add(url);
          storagePaths.add(path);
          mediaTypes.add('image');
        }
      } catch (e) {
        // Never create a treatment update whose media silently failed to
        // upload — leave the picked images in the form so Save can be
        // retried without having to re-pick them.
        if (mounted) {
          setState(() {
            _isSaving = false;
            _isUploadingMedia = false;
            _mediaError = 'Could not upload image: $e';
          });
        }
        return;
      }
      if (mounted) setState(() => _isUploadingMedia = false);
    }

    final entry = TreatmentLogEntry(
      id: '',
      caseId: widget.caseId,
      type: _selectedType!.label,
      notes: _notesController.text.trim(),
      condition: _isDeathReport
          ? 'Deceased'
          : (_isDischarge ? _finalCondition : _selectedCondition),
      medicationName:
          _selectedType == TreatmentUpdateType.medication ? _medicationNameController.text.trim() : null,
      medicationDose:
          _selectedType == TreatmentUpdateType.medication ? _medicationDoseController.text.trim() : null,
      procedurePerformed:
          _selectedType == TreatmentUpdateType.procedure ? _procedureController.text.trim() : null,
      vaccineName: _selectedType == TreatmentUpdateType.vaccination ? _vaccineNameController.text.trim() : null,
      vaccineDose: _selectedType == TreatmentUpdateType.vaccination ? _vaccineDoseController.text.trim() : null,
      nextScheduleAt: _selectedType == TreatmentUpdateType.vaccination ? _nextVaccineSchedule : null,
      dischargeNotes: _isDischarge ? _dischargeNotesController.text.trim() : null,
      finalCondition: _isDischarge ? _finalCondition : null,
      postTreatmentInstructions:
          _isDischarge ? _postTreatmentInstructionsController.text.trim() : null,
      dateOfDeath: _isDeathReport ? _treatmentDate : null,
      causeOfDeath: _isDeathReport ? _selectedCauseOfDeath : null,
      treatmentDate: _treatmentDate,
      mediaUrls: mediaUrls,
      mediaTypes: mediaTypes,
      storagePaths: storagePaths,
      createdBy: 'Admin Staff',
      animalIndexes: _updateAnimalIndexes.isEmpty ? null : _updateAnimalIndexes.toList(),
    );

    try {
      await repo.addTreatmentLog(caseId: widget.caseId, entry: entry, logId: logId);
      if (mounted) {
        setState(() {
          _showUpdateForm = false;
          _isSaving = false;
          _selectedType = null;
          _treatmentDate = _todayDateOnly();
          _selectedCondition = null;
          _finalCondition = null;
          _selectedCauseOfDeath = null;
          _notesController.clear();
          _medicationNameController.clear();
          _medicationDoseController.clear();
          _procedureController.clear();
          _vaccineNameController.clear();
          _vaccineDoseController.clear();
          _dischargeNotesController.clear();
          _postTreatmentInstructionsController.clear();
          _pickedMedia.clear();
          _mediaError = null;
          _updateAnimalIndexes = {};
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSaving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not save update: $e'), backgroundColor: Colors.redAccent),
        );
      }
    }
  }

  Future<void> _confirmNextStep(RescueCase c, Map<String, dynamic> data) async {
    if (_isActingOnNextStep || _selectedNextStep == null) return;
    setState(() => _isActingOnNextStep = true);

    switch (_selectedNextStep) {
      case _kNextStepIntake:
        if (mounted) {
          await Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => IntakeDetailPage(caseId: widget.caseId, data: data)),
          );
        }
        break;
      case _kNextStepTransfer:
        if (mounted) await showTransferAnimalSheet(context, rescueCase: c);
        break;
      case _kNextStepRelease:
        if (mounted) await showReleaseAnimalSheet(context, rescueCase: c);
        break;
    }

    if (mounted) setState(() => _isActingOnNextStep = false);
  }

  Future<void> _closeDeceasedCase(RescueCase c, double outstandingBalance) async {
    final dateOfDeath = c.deceasedAt;
    final dateStr = dateOfDeath != null
        ? '${dateOfDeath.month}/${dateOfDeath.day}/${dateOfDeath.year}'
        : '-';
    final confirmed = await showConfirmActionDialog(
      context,
      title: 'Close Case?',
      message: 'Case #${c.shortCaseId}\n${c.speciesSummary}\n\n'
          'Date of death: $dateStr\n'
          'Cause of death: ${c.causeOfDeath ?? '-'}\n'
          'Outstanding balance: ${formatPeso(outstandingBalance)}\n\n'
          'This preserves all treatment logs, expenses, and funding history.',
      confirmLabel: 'Close Case',
    );
    if (!confirmed || !mounted) return;

    try {
      await ref.read(rescueCaseRepositoryProvider).closeDeceasedCase(caseId: widget.caseId);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not close case: $e'), backgroundColor: Colors.redAccent),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final liveCase = ref.watch(caseDetailProvider(widget.caseId)).asData?.value;
    final c = liveCase ?? RescueCase.fromMap(widget.caseId, widget.data);
    final data = c.raw.isNotEmpty ? c.raw : widget.data;

    final logsAsync = ref.watch(treatmentLogsProvider(widget.caseId));
    final allLogs = (logsAsync.asData?.value ?? const <TreatmentLogEntry>[]).reversed.toList();

    // Most cases reach Treatment with no AnimalRecord created yet (that
    // normally happens at Intake) — namesByAnimalIndex is empty for those,
    // and every option falls back to a species-ordinal label ("Dog 1").
    final linkedRecords = ref.watch(recordsForCaseProvider(widget.caseId)).asData?.value ?? const [];
    final namesByAnimalIndex = <int, String>{
      for (final r in linkedRecords)
        if (r.sourceAnimalIndex != null && r.name.isNotEmpty) r.sourceAnimalIndex!: r.name,
    };
    final animalOptions = buildCaseAnimalOptions(c, namesByAnimalIndex: namesByAnimalIndex);
    final selectedAnimalIndex = _selectedAnimalIndex != null && _selectedAnimalIndex! < animalOptions.length
        ? _selectedAnimalIndex
        : null;

    final logs = selectedAnimalIndex == null
        ? allLogs
        : allLogs.where((l) => l.appliesToAnimal(selectedAnimalIndex)).toList();

    String? logAnimalLabel(TreatmentLogEntry log) {
      if (animalOptions.length <= 1) return null;
      if (log.appliesToAllAnimals) return 'All animals';
      final labels = <String>[];
      for (final i in log.animalIndexes!) {
        final match = animalOptions.where((o) => o.index == i);
        labels.add(match.isNotEmpty ? match.first.label : 'Animal ${i + 1}');
      }
      return labels.join(' and ');
    }

    final expensesAsync = ref.watch(expensesProvider(widget.caseId));
    final expenses = expensesAsync.asData?.value ?? const [];
    final totalExpenses = expenses.fold<double>(0, (sum, e) => sum + e.amount);
    final fundedAmount = expenses.where((e) => e.isFunded).fold<double>(0, (sum, e) => sum + e.amount);
    final outstandingBalance = totalExpenses - fundedAmount;

    final dateStr = c.dateAdmitted != null
        ? '${_monthName(c.dateAdmitted!.month)} ${c.dateAdmitted!.day}, ${c.dateAdmitted!.year}'
        : '-';

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.textPrimary,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppColors.background),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text('Treatment Details',
            style: GoogleFonts.tiltWarp(fontSize: 18, color: AppColors.background)),
        actions: [
          IconButton(
            icon: const Icon(Icons.notifications_outlined, color: AppColors.background),
            onPressed: () {},
          ),
          if (!c.isDeceased)
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert, color: AppColors.background),
              enabled: !_closingCase,
              onSelected: (_) => _closeCase(c),
              itemBuilder: (context) => const [
                PopupMenuItem(value: 'close_case', child: Text('Close Case')),
              ],
            ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header — Case ID is the primary identifier, no status chip.
            Text('#${c.shortCaseId}',
                style: GoogleFonts.tiltWarp(fontSize: 22, color: AppColors.textPrimary)),
            const SizedBox(height: 2),
            Text(c.speciesSummary,
                style: GoogleFonts.zain(
                    fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
            if ((c.vetClinicName ?? '').isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(c.vetClinicName!,
                  style: GoogleFonts.zain(fontSize: 13, color: AppColors.textSecondary)),
            ],
            const SizedBox(height: 2),
            Text('Admitted $dateStr',
                style: GoogleFonts.zain(fontSize: 12, color: AppColors.textSecondary)),

            const SizedBox(height: 16),

            // Info grid
            Row(
              children: [
                Expanded(child: _InfoItem('Days in Treatment', '${c.daysInTreatment}')),
                Expanded(child: _InfoItem('Number of Animals', '${c.animalCount}')),
              ],
            ),
            Row(
              children: [
                Expanded(
                  child: _InfoItem(
                    'Latest Condition',
                    c.isDeceased ? 'Deceased' : (c.currentCondition ?? '-'),
                  ),
                ),
                Expanded(child: _InfoItem('Reported by', c.reporterName ?? '-')),
              ],
            ),

            if (animalOptions.length > 1) ...[
              const SizedBox(height: 16),
              CaseAnimalSelectorBar(
                options: animalOptions,
                selected: selectedAnimalIndex,
                onChanged: (v) => setState(() {
                  _selectedAnimalIndex = v;
                  _showAllLogs = false;
                }),
              ),
            ],

            const SizedBox(height: 16),

            // Treatment Logs
            Text('Treatment Logs',
                style: GoogleFonts.tiltWarp(fontSize: 15, color: AppColors.textPrimary)),
            const SizedBox(height: 8),

            if (logsAsync.isLoading && logs.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (logs.isEmpty)
              Text(
                  selectedAnimalIndex == null
                      ? 'No treatment logs yet.'
                      : 'No treatment logs for this animal yet.',
                  style: GoogleFonts.zain(fontSize: 13, color: AppColors.textSecondary))
            else ...[
              ...(_showAllLogs ? logs : logs.take(2).toList())
                  .map((log) => TreatmentLogCard(log: log, animalLabel: logAnimalLabel(log))),
              if (logs.length > 2)
                Center(
                  child: GestureDetector(
                    onTap: () => setState(() => _showAllLogs = !_showAllLogs),
                    child: Padding(
                      padding: const EdgeInsets.all(8),
                      child: Icon(
                        _showAllLogs ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ),
                ),
            ],

            const SizedBox(height: 24),

            // Add Update — kept directly above Cost Tracking (not below it)
            // so the button and the form it opens stay together, instead of
            // the old layout where tapping "Add Update" revealed a form the
            // admin had already scrolled past.
            if (!c.isDeceased) ...[
              if (c.readyForDischarge)
                const _DischargedNotice()
              else ...[
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: () => setState(() {
                      _showUpdateForm = !_showUpdateForm;
                      // Defaults the new update's "Applies to" to whatever
                      // animal is currently in view, so filling out a form
                      // while viewing one animal's timeline doesn't
                      // silently default to All Animals underneath it.
                      if (_showUpdateForm) {
                        _updateAnimalIndexes = selectedAnimalIndex != null ? {selectedAnimalIndex} : {};
                      }
                    }),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: AppColors.textPrimary),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    child: Text(_showUpdateForm ? 'Hide Form' : 'Add Update',
                        style: GoogleFonts.tiltWarp(fontSize: 15, color: AppColors.textPrimary)),
                  ),
                ),
                if (_showUpdateForm) ...[
                  const SizedBox(height: 16),
                  _buildUpdateForm(animalOptions),
                ],
              ],
              const SizedBox(height: 24),
            ],

            _CostTrackingSection(
              caseId: widget.caseId,
              rescueCase: c,
              allExpenses: expenses,
              totalExpenses: totalExpenses,
              fundedAmount: fundedAmount,
              outstandingBalance: outstandingBalance,
              animalOptions: animalOptions,
              selectedAnimalIndex: selectedAnimalIndex,
            ),

            const SizedBox(height: 32),

            if (c.isDeceased)
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => _closeDeceasedCase(c, outstandingBalance),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.yellowrspwn,
                    elevation: 0,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  child: Text('Close Case',
                      style: GoogleFonts.tiltWarp(fontSize: 16, color: AppColors.textPrimary)),
                ),
              )
            // The post-treatment dropdown only becomes available once a
            // Discharge update has actually been saved — never enabled just
            // because the animal "seems" ready.
            else if (c.readyForDischarge) ...[
              Text('Post-Treatment Disposition',
                  style: GoogleFonts.tiltWarp(fontSize: 15, color: AppColors.textPrimary)),
              const SizedBox(height: 8),
              _NextStepDropdown(
                value: _selectedNextStep,
                allowRelease: (c.interestedToAdopt ?? '').toLowerCase() == 'yes',
                onChanged: (v) => setState(() => _selectedNextStep = v),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: (_selectedNextStep == null || _isActingOnNextStep)
                      ? null
                      : () => _confirmNextStep(c, data),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.yellowrspwn,
                    disabledBackgroundColor: AppColors.slaterspwn,
                    elevation: 0,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  child: _isActingOnNextStep
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.textPrimary))
                      : Text(_nextStepButtonLabel(),
                          style: GoogleFonts.tiltWarp(fontSize: 15, color: AppColors.textPrimary)),
                ),
              ),
            ],

            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  String _nextStepButtonLabel() => switch (_selectedNextStep) {
        _kNextStepIntake => 'Proceed to Intake',
        _kNextStepTransfer => 'Transfer Animal',
        _kNextStepRelease => 'Release Animal',
        _ => 'Choose Next Step',
      };

  Widget _buildUpdateForm(List<CaseAnimalOption> animalOptions) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Enter Treatment Update',
            style: GoogleFonts.tiltWarp(fontSize: 16, color: AppColors.textPrimary)),
        const SizedBox(height: 16),

        // Required per spec: One animal / Multiple animals / All animals.
        // Only shown for a multi-animal case — a single-animal case has
        // nothing to choose between, so this stays hidden and every log
        // implicitly applies to that one animal (animalIndexes left null).
        if (animalOptions.length > 1) ...[
          _FieldLabel('Applies to', required: true),
          const SizedBox(height: 4),
          CaseAnimalMultiSelectBar(
            options: animalOptions,
            selected: _updateAnimalIndexes,
            onChanged: (next) => setState(() => _updateAnimalIndexes = next),
          ),
          const SizedBox(height: 16),
        ],

        // Date only — defaults to today when the form opens (see initState /
        // _addUpdate's reset), never a time picker. Only a manual change
        // via this date picker moves it off today.
        _FieldLabel('Date', required: true),
        GestureDetector(
          onTap: () async {
            final now = DateTime.now();
            final picked = await showDatePicker(
              context: context,
              initialDate: _treatmentDate ?? _todayDateOnly(),
              firstDate: DateTime(2020),
              lastDate: now,
            );
            if (picked != null) setState(() => _treatmentDate = DateTime(picked.year, picked.month, picked.day));
          },
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 12),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: AppColors.textPrimary)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  _treatmentDate == null
                      ? 'mm/dd/yyyy'
                      : '${_treatmentDate!.month}/${_treatmentDate!.day}/${_treatmentDate!.year}',
                  style: GoogleFonts.zain(
                      fontSize: 14,
                      color: _treatmentDate == null ? AppColors.textSecondary : AppColors.textPrimary),
                ),
                const Icon(Icons.calendar_today_outlined, size: 18, color: AppColors.textPrimary),
              ],
            ),
          ),
        ),

        const SizedBox(height: 16),
        _FieldLabel('Update Type', required: true),
        _Dropdown<TreatmentUpdateType>(
          value: _selectedType,
          hint: 'Select',
          items: TreatmentUpdateType.values,
          labelOf: (t) => t.label,
          onChanged: (val) => setState(() => _selectedType = val),
        ),
        const SizedBox(height: 16),

        // Fields shown/hidden by update type, per spec.
        if (_selectedType == TreatmentUpdateType.medication) ...[
          _FieldLabel('Medication Name'),
          _TextInput(controller: _medicationNameController, hint: 'e.g. Amoxicillin'),
          const SizedBox(height: 12),
          _FieldLabel('Dose'),
          _TextInput(controller: _medicationDoseController, hint: 'e.g. 250mg twice daily'),
          const SizedBox(height: 16),
        ],
        if (_selectedType == TreatmentUpdateType.procedure) ...[
          _FieldLabel('Procedure Performed'),
          _TextInput(controller: _procedureController, hint: 'e.g. Wound cleaning and suturing'),
          const SizedBox(height: 16),
        ],
        if (_selectedType == TreatmentUpdateType.vaccination) ...[
          _FieldLabel('Vaccine'),
          _TextInput(controller: _vaccineNameController, hint: 'e.g. Anti-rabies'),
          const SizedBox(height: 12),
          _FieldLabel('Dose'),
          _TextInput(controller: _vaccineDoseController, hint: 'e.g. 1ml'),
          const SizedBox(height: 12),
          _FieldLabel('Next Schedule (optional)'),
          GestureDetector(
            onTap: () async {
              final picked = await showDatePicker(
                context: context,
                initialDate: DateTime.now(),
                firstDate: DateTime.now(),
                lastDate: DateTime(2100),
              );
              if (picked != null) setState(() => _nextVaccineSchedule = picked);
            },
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 12),
              decoration: const BoxDecoration(
                border: Border(bottom: BorderSide(color: AppColors.textPrimary)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    _nextVaccineSchedule == null
                        ? 'mm/dd/yyyy'
                        : '${_nextVaccineSchedule!.month}/${_nextVaccineSchedule!.day}/${_nextVaccineSchedule!.year}',
                    style: GoogleFonts.zain(fontSize: 14, color: AppColors.textSecondary),
                  ),
                  const Icon(Icons.calendar_today_outlined, size: 18, color: AppColors.textPrimary),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
        ],
        if (_isDischarge) ...[
          _FieldLabel('Discharge Notes', required: true),
          _TextInput(controller: _dischargeNotesController, hint: 'Enter discharge notes'),
          const SizedBox(height: 12),
          _FieldLabel('Final Condition', required: true),
          _Dropdown<String>(
            value: _finalCondition,
            hint: 'Select',
            items: _conditions,
            labelOf: (s) => s,
            onChanged: (val) => setState(() => _finalCondition = val),
          ),
          const SizedBox(height: 12),
          _FieldLabel('Post-Treatment Instructions'),
          _TextInput(
              controller: _postTreatmentInstructionsController, hint: 'e.g. Keep wound dry for 5 days'),
          const SizedBox(height: 16),
        ],
        if (_isDeathReport) ...[
          _FieldLabel('Cause of Death', required: true),
          _Dropdown<String>(
            value: _selectedCauseOfDeath,
            hint: 'Select',
            items: _causesOfDeath,
            labelOf: (s) => s,
            onChanged: (val) => setState(() => _selectedCauseOfDeath = val),
          ),
          const SizedBox(height: 16),
        ],
        if (!_isDischarge && !_isDeathReport) ...[
          _FieldLabel('Overall Condition', required: true),
          _Dropdown<String>(
            value: _selectedCondition,
            hint: 'Select',
            items: _conditions,
            labelOf: (s) => s,
            onChanged: (val) => setState(() => _selectedCondition = val),
          ),
          const SizedBox(height: 16),
        ],

        _FieldLabel('Notes', required: true),
        _TextInput(controller: _notesController, hint: 'Enter notes'),

        const SizedBox(height: 16),
        _FieldLabel('Include images'),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (var i = 0; i < _pickedMedia.length; i++) _PickedImageThumb(file: _pickedMedia[i], onRemove: _isSaving ? null : () => _removeMedia(i)),
            GestureDetector(
              onTap: _isSaving ? null : _pickFromGallery,
              child: Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  border: Border.all(color: AppColors.greenrspwn, width: 1.5),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.add_photo_alternate_outlined, size: 24, color: AppColors.greenrspwn),
              ),
            ),
            GestureDetector(
              onTap: _isSaving ? null : _pickFromCamera,
              child: Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  border: Border.all(color: AppColors.slaterspwn, width: 1.5),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.camera_alt_outlined, size: 24, color: AppColors.textSecondary),
              ),
            ),
          ],
        ),
        if (_isUploadingMedia) ...[
          const SizedBox(height: 10),
          Row(
            children: [
              const SizedBox(
                  width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)),
              const SizedBox(width: 8),
              Text('Uploading images…', style: GoogleFonts.zain(fontSize: 12, color: AppColors.textSecondary)),
            ],
          ),
        ],
        if (_mediaError != null) ...[
          const SizedBox(height: 10),
          Text(_mediaError!, style: GoogleFonts.zain(fontSize: 12, color: Colors.redAccent)),
        ],

        const SizedBox(height: 24),
        Center(
          child: ElevatedButton(
            onPressed: (_isSaving || !_canSubmit()) ? null : _addUpdate,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.yellowrspwn,
              disabledBackgroundColor: AppColors.slaterspwn,
              fixedSize: Size(MediaQuery.of(context).size.width * 0.5, 48),
              elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
            ),
            child: _isSaving
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.textPrimary))
                : Text(_mediaError != null ? 'Retry' : 'Add', style: GoogleFonts.tiltWarp(fontSize: 16, color: AppColors.textPrimary)),
          ),
        ),
      ],
    );
  }
}

String _monthName(int month) => const [
      'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December',
    ][month - 1];

/// Replaces the "Add Update" button once `readyForDischarge == true` —
/// disabled rather than hidden, so it's clear the option existed and is now
/// closed off, not just missing. The actual enforcement is in the
/// repository (RescueCaseRepository.addTreatmentLog); this is the UI half.
class _DischargedNotice extends StatelessWidget {
  const _DischargedNotice();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        OutlinedButton(
          onPressed: null,
          style: OutlinedButton.styleFrom(
            disabledForegroundColor: AppColors.textSecondary,
            side: const BorderSide(color: AppColors.slaterspwn),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
            padding: const EdgeInsets.symmetric(vertical: 14),
          ),
          child: Text('Treatment Discharged',
              style: GoogleFonts.tiltWarp(fontSize: 15, color: AppColors.textSecondary)),
        ),
        const SizedBox(height: 6),
        Text('No further treatment updates can be added after discharge.',
            textAlign: TextAlign.center,
            style: GoogleFonts.zain(fontSize: 11, color: AppColors.textSecondary)),
      ],
    );
  }
}

class _NextStepDropdown extends StatelessWidget {
  final String? value;
  final bool allowRelease;
  final ValueChanged<String?> onChanged;
  const _NextStepDropdown({required this.value, required this.allowRelease, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final items = [
      _kNextStepIntake,
      _kNextStepTransfer,
      // Only offered when the reporter indicated adoption interest at
      // submission time — see RescueCase.interestedToAdopt.
      if (allowRelease) _kNextStepRelease,
    ];
    return DropdownButtonFormField<String>(
      value: items.contains(value) ? value : null,
      hint: Text('Choose Next Step',
          style: GoogleFonts.zain(fontSize: 14, color: AppColors.textSecondary)),
      style: GoogleFonts.zain(fontSize: 14, color: AppColors.textPrimary),
      decoration: const InputDecoration(
        isDense: true,
        contentPadding: EdgeInsets.only(bottom: 8),
        enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: AppColors.textPrimary)),
        focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: AppColors.textPrimary, width: 1.5)),
      ),
      items: items
          .map((i) => DropdownMenuItem(
              value: i, child: Text(i, style: GoogleFonts.zain(fontSize: 14, color: AppColors.textPrimary))))
          .toList(),
      onChanged: onChanged,
    );
  }
}

class _CostTrackingSection extends StatelessWidget {
  final String caseId;
  final RescueCase rescueCase;
  final List<Expense> allExpenses;
  final double totalExpenses;
  final double fundedAmount;
  final double outstandingBalance;
  final List<CaseAnimalOption> animalOptions;
  final int? selectedAnimalIndex;

  const _CostTrackingSection({
    required this.caseId,
    required this.rescueCase,
    required this.allExpenses,
    required this.totalExpenses,
    required this.fundedAmount,
    required this.outstandingBalance,
    required this.animalOptions,
    required this.selectedAnimalIndex,
  });

  @override
  Widget build(BuildContext context) {
    // Total/Funded/Outstanding always reflect the whole case (never
    // filtered by animal — Close Case's own financial summary and every
    // other reader of these totals expects the case-wide figure). The
    // per-animal breakdown below is purely additional, computed from the
    // same list, and never sums to more than totalExpenses since a shared
    // expense is counted once here, not once per animal.
    final breakdown = <String, double>{};
    if (animalOptions.length > 1) {
      var shared = 0.0;
      for (final e in allExpenses) {
        if (e.isSharedCaseExpense) {
          shared += e.amount;
        } else {
          for (final i in e.animalIndexes!) {
            final match = animalOptions.where((o) => o.index == i);
            final label = match.isNotEmpty ? match.first.label : 'Animal ${i + 1}';
            breakdown[label] = (breakdown[label] ?? 0) + e.amount;
          }
        }
      }
      if (shared > 0) breakdown['Shared Expenses'] = shared;
    }

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.slaterspwn),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Cost Tracking',
              style: GoogleFonts.tiltWarp(fontSize: 15, color: AppColors.textPrimary)),
          const SizedBox(height: 10),
          _CostRow('Total Case Cost', totalExpenses),
          _CostRow('Funded Amount', fundedAmount),
          _CostRow('Outstanding Balance', outstandingBalance, emphasize: true),
          if (breakdown.isNotEmpty) ...[
            const SizedBox(height: 8),
            const Divider(height: 1, color: AppColors.slaterspwn),
            const SizedBox(height: 8),
            for (final entry in breakdown.entries) _CostRow(entry.key, entry.value),
          ],
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton(
                onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => ExpenseListPage(
                              caseId: caseId,
                              animalOptions: animalOptions,
                              initialAnimalIndex: selectedAnimalIndex,
                            ))),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.textPrimary,
                  side: const BorderSide(color: AppColors.textPrimary),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                ),
                child: Text('View Expenses', style: GoogleFonts.zain(fontSize: 12, fontWeight: FontWeight.w600)),
              ),
              ElevatedButton(
                onPressed: () => showAddEditExpenseSheet(
                  context,
                  caseId: caseId,
                  animalOptions: animalOptions,
                  initialAnimalIndexes: selectedAnimalIndex != null ? {selectedAnimalIndex!} : const {},
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.yellowrspwn,
                  // Explicit foreground — without it this falls back to the
                  // theme's ColorScheme.onPrimary, which (since the app
                  // theme overrides `primary` to yellowrspwn without
                  // recomputing onPrimary to match) is too close to the
                  // yellow background to read. Same fix as the other
                  // primary yellow buttons in this file.
                  foregroundColor: AppColors.textPrimary,
                  elevation: 0,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                ),
                child: Text('Add Expense',
                    style: GoogleFonts.zain(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
              ),
              OutlinedButton(
                onPressed: outstandingBalance <= 0
                    ? null
                    : () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => CreateFundraiserDraftPage(
                            rescueCase: rescueCase,
                            outstandingBalance: outstandingBalance,
                          ),
                        )),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.textPrimary,
                  side: const BorderSide(color: AppColors.textPrimary),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                ),
                child: Text('Create Fundraiser', style: GoogleFonts.zain(fontSize: 12, fontWeight: FontWeight.w600)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _CostRow extends StatelessWidget {
  final String label;
  final double amount;
  final bool emphasize;
  const _CostRow(this.label, this.amount, {this.emphasize = false});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: GoogleFonts.zain(fontSize: 13, color: AppColors.textSecondary)),
          Text(formatPeso(amount),
              style: GoogleFonts.zain(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: emphasize ? AppColors.textPrimary : AppColors.textSecondary)),
        ],
      ),
    );
  }
}

class _InfoItem extends StatelessWidget {
  final String label;
  final String value;
  const _InfoItem(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: GoogleFonts.zain(fontSize: 12, color: AppColors.textSecondary)),
          Text(value,
              style: GoogleFonts.zain(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
        ],
      ),
    );
  }
}

class _FieldLabel extends StatelessWidget {
  final String label;
  final bool required;
  const _FieldLabel(this.label, {this.required = false});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(label,
            style: GoogleFonts.zain(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
        if (required) const Text(' *', style: TextStyle(color: Colors.red, fontSize: 14)),
      ],
    );
  }
}

class _TextInput extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  const _TextInput({required this.controller, required this.hint});

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: GoogleFonts.zain(color: AppColors.textSecondary, fontSize: 14),
        enabledBorder: const UnderlineInputBorder(borderSide: BorderSide(color: AppColors.textPrimary)),
        focusedBorder:
            const UnderlineInputBorder(borderSide: BorderSide(color: AppColors.textPrimary, width: 1.5)),
        isDense: true,
        contentPadding: const EdgeInsets.only(bottom: 8),
      ),
      style: GoogleFonts.zain(fontSize: 14, color: AppColors.textPrimary),
    );
  }
}

class _PickedImageThumb extends StatelessWidget {
  final XFile file;
  final VoidCallback? onRemove;
  const _PickedImageThumb({required this.file, required this.onRemove});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 72,
      height: 72,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.file(File(file.path), width: 72, height: 72, fit: BoxFit.cover),
          ),
          if (onRemove != null)
            Positioned(
              top: -6,
              right: -6,
              child: GestureDetector(
                onTap: onRemove,
                child: Container(
                  padding: const EdgeInsets.all(2),
                  decoration: const BoxDecoration(color: Color(0xFFE05353), shape: BoxShape.circle),
                  child: const Icon(Icons.close, size: 14, color: Colors.white),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _Dropdown<T> extends StatelessWidget {
  final T? value;
  final String hint;
  final List<T> items;
  final String Function(T) labelOf;
  final ValueChanged<T?> onChanged;

  const _Dropdown({
    required this.value,
    required this.hint,
    required this.items,
    required this.labelOf,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<T>(
      value: value,
      hint: Text(hint, style: GoogleFonts.zain(fontSize: 14, color: AppColors.textSecondary)),
      style: GoogleFonts.zain(fontSize: 14, color: AppColors.textPrimary),
      decoration: const InputDecoration(
        isDense: true,
        contentPadding: EdgeInsets.only(bottom: 8),
        enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: AppColors.textPrimary)),
        focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: AppColors.textPrimary, width: 1.5)),
      ),
      items: items
          .map((item) => DropdownMenuItem(
              value: item,
              child: Text(labelOf(item), style: GoogleFonts.zain(fontSize: 14, color: AppColors.textPrimary))))
          .toList(),
      onChanged: onChanged,
    );
  }
}
