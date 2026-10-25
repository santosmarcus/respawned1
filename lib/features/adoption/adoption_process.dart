import 'dart:async';
import 'package:respawnd1/core/widgets/image_source_sheet.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:respawnd1/app_theme.dart';
import 'adoption_page.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:io';
import 'package:image_picker/image_picker.dart';
import 'package:respawnd1/core/models/adoption/adoption_application.dart';
import 'package:respawnd1/features/adoption/services/adoption_application_service.dart';
import 'package:respawnd1/features/adoption/adoption_form_controller.dart';
import 'package:respawnd1/features/adoption/adoption_step.dart';
import 'package:respawnd1/features/adoption/steps/adoption_day_step.dart';
import 'package:respawnd1/features/adoption/steps/adoption_intro_step.dart';
import 'package:respawnd1/features/adoption/steps/application_review_step.dart';
import 'package:respawnd1/features/adoption/steps/application_update_step.dart';
import 'package:respawnd1/features/adoption/steps/book_appointment_step.dart';
import 'package:respawnd1/features/adoption/steps/time_to_meet_step.dart';
import 'package:respawnd1/features/adoption/steps/withdrawn_step.dart';
import 'package:respawnd1/features/adoption/widgets/adoption_step_tracker.dart';

// widget.animal is now always built from a live AnimalRecord
// (adoption_page.dart's animalRecordToCard) — the old hardcoded catalog
// this comment used to describe is gone. `widget.animal.id` is still a
// one-way stableIntIdFor hash of the real animal document id (kept only so
// this legacy int-keyed screen/AdoptionProcess/favorites pipeline doesn't
// need rewiring), so it can never be reversed back into a real
// `animals/{id}` id for a Firestore document lookup. Real
// document/query operations against the `animals` collection (reserve,
// clearReservationOnWithdrawal, admin-side "View Applications" linking)
// must use `widget.animal.animalRecordId` instead — the actual Firestore
// id, carried alongside `id` for exactly this purpose. `personal.animalId`
// stays on the submitted document only for backward-compatible display/
// dedupe matching against older applications written the same way;
// `personal.animalRecordId` (added below) is the real, reliable join key.
class AdoptionProcess extends StatefulWidget {
  final Animal animal;
  final String? existingAdoptionId;
  const AdoptionProcess({
    super.key,
    required this.animal,
    this.existingAdoptionId,
  });
  @override
  State<AdoptionProcess> createState() => _AdoptionProcessState();
}

class _AdoptionProcessState extends State<AdoptionProcess> {
  final AdoptionFormController _form = AdoptionFormController();

  final _picker = ImagePicker();
  final _service = AdoptionApplicationService();
  AdoptionStep _step = AdoptionStep.intro;

  String? _adoptionId;
  bool _isSubmitting = false;
  bool _isLoadingExisting = false;

  // True once the organization has reserved this animal for this
  // applicant's approved application (AdoptionApplicationRepository.reserve,
  // admin-side) — read straight off this same doc's own reservedAt field,
  // no second lookup needed.
  bool _isReservedForMe = false;

  // Live updates so admin actions (interview scheduling, approval,
  // reservation, release, rejection) show up here without the applicant
  // needing to reopen this screen.
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _adoptionSub;

  // Delivery — set by the organization once the animal is released (see
  // ReleaseDetailsPage's Release / Adoption Date, admin-side). Carries a
  // real time-of-day (not just midnight) once that screen's date+time
  // picker is used, so this doubles as both the "adoption day" gate below
  // and the date/time actually shown to the adopter here.
  DateTime? _scheduledReleaseDate;
  // How many delivery attempts have been used so far (each one spent by a
  // reschedule request — see _requestDeliveryReschedule). Capped at
  // kMaxDeliveryAttempts (shared with the admin Release page — see
  // AdoptionApplication — so the two screens can never disagree); the
  // Request Reschedule button disables itself once that cap is hit.
  int _deliveryAttempts = 0;

  AdoptionStep? _reviewStep;

  AdoptionStep get _displayStep => _reviewStep ?? _step;

  bool get _isReadOnly => _reviewStep != null;

  int get _displayIndex {
    final idx = kAdoptionTrackerSteps.indexOf(_displayStep);
    return idx == -1 ? _activeStepIndex : idx;
  }

  void _onTrackerTap(int index) {
    if (index > _activeStepIndex) return; // hasn't reached that phase yet
    final target = kAdoptionTrackerSteps[index];
    setState(() => _reviewStep = target == _step ? null : target);
  }

  @override
  void initState() {
    super.initState();
    if (widget.existingAdoptionId != null) {
      _isLoadingExisting = true;
      _loadExistingAdoption();
      _adoptionSub = _service
          .watchApplication(widget.existingAdoptionId!)
          .listen((_) {
            // Re-parses via the same _loadExistingAdoption path used on open —
            // no separate live-parsing logic to keep in sync with it.
            if (!_isLoadingExisting) _loadExistingAdoption();
          });
    } else {
      _prefillFromAccount();
    }
  }

  @override
  void dispose() {
    _adoptionSub?.cancel();
    _form.dispose();
    super.dispose();
  }

  int get _activeStepIndex => adoptionTrackerIndex(_step);

  //select image
  Future<void> _pickUploadFile({required void Function(File) onPicked}) async {
    final picked = await pickImageWithSource(context, _picker, maxWidth: 1280);
    if (picked != null) {
      onPicked(File(picked.path));
    }
  }

  static const _maxHomePhotos = 6;

  /// Adds to the existing selection rather than replacing it — repeated
  /// taps let the applicant keep adding more photos, matching "allow
  /// adding more images afterward." Capped at [_maxHomePhotos] total
  /// (existing + newly picked combined) — extra picks beyond the cap are
  /// dropped with a message rather than silently accepted.
  Future<void> _addHomePhotos() async {
    final picked = await pickImagesWithSource(context, _picker);
    if (picked.isEmpty) return;

    final currentTotal =
        _form.existingHomePhotoUrls.length + _form.homePhotosFiles.length;
    final room = _maxHomePhotos - currentTotal;
    if (room <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('You can upload at most $_maxHomePhotos home photos.'),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }

    final accepted = picked.take(room).toList();
    if (accepted.length < picked.length && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Only $room more photo(s) can be added (max $_maxHomePhotos total).',
          ),
          backgroundColor: Colors.redAccent,
        ),
      );
    }
    setState(
      () => _form.homePhotosFiles.addAll(accepted.map((x) => File(x.path))),
    );
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: now.add(const Duration(days: 3)),
      firstDate: now.add(const Duration(days: 1)),
      lastDate: now.add(const Duration(days: 90)),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: AppColors.greenrspwn,
              onPrimary: AppColors.textPrimary,
              surface: AppColors.background,
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null) setState(() => _form.appointmentDate = picked);
  }

  //Firestore Helpers
  Future<void> _prefillFromAccount() async {
    try {
      final data = await _service.fetchCurrentUserProfile();
      if (data == null) return;

      setState(() {
        _form.fillFromAccount(data, authEmail: _service.currentUserEmail);
      });
    } catch (_) {}
  }

  // Status -> step mapping (including legacy statuses) lives in
  // adoption_step.dart: adoptionStepForStatus / resolveAdoptionStep.

  // Reloads every saved answer
  Future<void> _loadExistingAdoption() async {
    final id = widget.existingAdoptionId;
    if (id == null) return;

    try {
      final data = await _service.fetchApplication(id);
      if (data == null) {
        if (mounted) setState(() => _isLoadingExisting = false);
        return;
      }

      final loadedStatus = data['status'] as String?;
      if (loadedStatus == 'withdrawn' || loadedStatus == 'rejected') {
        if (mounted) setState(() => _isLoadingExisting = false);
        await _prefillFromAccount();
        return;
      }

      final appointmentTs = data['appointmentDate'];

      setState(() {
        _adoptionId = id;

        _form.applySavedApplication(data);

        // Set by AdoptionApplicationRepository.reserve (admin-side) —
        // cleared again by unreserve/release.
        _isReservedForMe = data['reservedAt'] != null;

        // Delivery — written by ReleaseDetailsPage/releaseWithFollowUps
        // (admin-side) once the org schedules/marks the animal released.
        // ReleaseDetailsPage can also write a *draft* scheduledReleaseDate
        // while the admin is still configuring things (before "Mark as
        // Released" is actually pressed) — only treat it as a real,
        // finalized delivery once the application's own status confirms
        // the release actually went through, so the adopter never sees a
        // "Delivery scheduled" card for a date that isn't committed yet.
        final rawStatus = data['status'] as String?;
        final releaseDateTs = data['scheduledReleaseDate'];
        _scheduledReleaseDate =
            (kAdoptionReleasedStatuses.contains(rawStatus) &&
                releaseDateTs is Timestamp)
            ? releaseDateTs.toDate()
            : null;
        _deliveryAttempts = data['deliveryAttempts'] as int? ?? 0;

        _step = resolveAdoptionStep(
          rawStatus,
          hasAppointment: appointmentTs is Timestamp,
          scheduledReleaseDate: _scheduledReleaseDate,
          now: DateTime.now(),
        );
        _isLoadingExisting = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() => _isLoadingExisting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to load your application: $e'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  Future<void> _submitAdoptionForm() async {
    if (!(_form.formKey.currentState?.validate() ?? false)) return;

    // AdoptionRadioGroup/the caregiver dropdown aren't FormFields, so
    // _form.formKey.validate() above never sees them — every radio question in
    // this form could previously be submitted unanswered.
    final missingAnswers = _form.missingRequiredAnswers();
    if (missingAnswers.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Please answer: ${missingAnswers.join(', ')}.'),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }

    if (!_form.allAgreementsAccepted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please accept all agreements before submitting.'),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      final stillActiveOrDone = await _service.hasBlockingApplication(
        widget.animal,
      );

      if (stillActiveOrDone) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                '${widget.animal.name} already has an ongoing or completed adoption.',
              ),
              backgroundColor: Colors.redAccent,
            ),
          );
          setState(() => _isSubmitting = false);
        }
        return;
      }

      final newId = await _service.submitApplication(
        animal: widget.animal,
        form: _form,
      );

      setState(() {
        _adoptionId = newId;
        _step = AdoptionStep.bookAppointment;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to submit: $e'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  Future<void> _saveAppointment() async {
    if (_adoptionId == null) return;
    setState(() => _isSubmitting = true);

    try {
      await _service.saveAppointment(_adoptionId!, _form);

      setState(() => _step = AdoptionStep.appReview);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to book appointment: $e'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  // Clears every field back to a blank application
  void _resetProcessState() {
    _adoptionId = null;
    _step = AdoptionStep.intro;
    _reviewStep = null;
    _form.reset();
  }

  Future<void> _withdrawApplication() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.background,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          'Withdraw Application?',
          style: GoogleFonts.tiltWarp(
            fontWeight: FontWeight.bold,
            color: AppColors.textPrimary,
          ),
        ),
        content: Text(
          'Are you sure you want to withdraw your adoption application for ${widget.animal.name}? This action cannot be undone.',
          style: GoogleFonts.zain(fontSize: 14, color: AppColors.textPrimary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(
              'Cancel',
              style: GoogleFonts.zain(
                fontWeight: FontWeight.w600,
                color: AppColors.textSecondary,
              ),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              'Withdraw',
              style: GoogleFonts.zain(
                fontWeight: FontWeight.w700,
                color: Colors.redAccent,
              ),
            ),
          ),
        ],
      ),
    );

    if (confirmed != true || _adoptionId == null || !mounted) return;

    setState(() => _isSubmitting = true);
    try {
      await _service.withdraw(
        adoptionId: _adoptionId!,
        animalRecordId: widget.animal.animalRecordId,
      );

      setState(() => _step = AdoptionStep.withdrawn);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to withdraw: $e'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  /// Lets the adopter ask the organization to move the scheduled delivery
  /// date/time, capped at [kMaxDeliveryAttempts] total requests. Doesn't
  /// pick a new date itself — that stays with the organization — this just
  /// records the request (and spends one attempt) so the org can follow up.
  Future<void> _requestDeliveryReschedule() async {
    if (_adoptionId == null || _deliveryAttempts >= kMaxDeliveryAttempts) {
      return;
    }

    final nextAttempt = _deliveryAttempts + 1;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.background,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          'Request Reschedule?',
          style: GoogleFonts.tiltWarp(
            fontWeight: FontWeight.bold,
            color: AppColors.textPrimary,
          ),
        ),
        content: Text(
          'This will use attempt $nextAttempt of $kMaxDeliveryAttempts. The '
          'organization will reach out to arrange a new delivery date '
          'and time for ${widget.animal.name}.',
          style: GoogleFonts.zain(fontSize: 14, color: AppColors.textPrimary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(
              'Cancel',
              style: GoogleFonts.zain(
                fontWeight: FontWeight.w600,
                color: AppColors.textSecondary,
              ),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              'Request',
              style: GoogleFonts.zain(
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );

    if (confirmed != true || _adoptionId == null || !mounted) return;

    setState(() => _isSubmitting = true);
    try {
      await _service.requestDeliveryReschedule(
        adoptionId: _adoptionId!,
        nextAttempt: nextAttempt,
        maxAttempts: kMaxDeliveryAttempts,
      );

      if (mounted) setState(() => _deliveryAttempts = nextAttempt);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to request reschedule: $e'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  //Build
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: const Icon(
                      Icons.close,
                      size: 22,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Text(
                      'Adopt ${widget.animal.name}',
                      style: GoogleFonts.tiltWarp(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            // Tracker — tap a circle for a phase you've already reached to
            // review it (read-only); tap the current one again to return.
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: AdoptionStepTracker(
                labels: kAdoptionStepLabels,
                activeIndex: _activeStepIndex,
                displayIndex: _displayIndex,
                rejected:
                    _step == AdoptionStep.appReject ||
                    _step == AdoptionStep.withdrawn,
                onStepTap: _onTrackerTap,
              ),
            ),

            if (_isReadOnly) ...[
              const SizedBox(height: 14),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.slaterspwn.withValues(alpha: 0.35),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.visibility_outlined,
                        size: 16,
                        color: AppColors.textPrimary,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Viewing a previous step — read only. Tap your '
                          'current step\'s circle above to return.',
                          style: GoogleFonts.zain(
                            fontSize: 12,
                            color: AppColors.textPrimary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],

            const SizedBox(height: 24),

            // body
            Expanded(
              child: _isLoadingExisting
                  ? const Center(
                      child: CircularProgressIndicator(
                        color: AppColors.greenrspwn,
                      ),
                    )
                  : SingleChildScrollView(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: IgnorePointer(
                        ignoring: _isReadOnly,
                        child: _buildStepBody(),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  /// Rebuild after a step widget mutated [_form] (the steps call this where
  /// the page used to call `setState` directly).
  void _onFormChanged() => setState(() {});

  // switcher — the AdoptionStep enum decides which step widget is shown.
  Widget _buildStepBody() {
    switch (_displayStep) {
      case AdoptionStep.intro:
        return AdoptionIntroStep(
          form: _form,
          readOnly: _isReadOnly,
          isSubmitting: _isSubmitting,
          onAddHomePhotos: _addHomePhotos,
          onPickUploadFile: _pickUploadFile,
          onSubmit: _submitAdoptionForm,
          onChanged: _onFormChanged,
        );
      case AdoptionStep.bookAppointment:
        return BookAppointmentStep(
          form: _form,
          readOnly: _isReadOnly,
          isSubmitting: _isSubmitting,
          onSaveAppointment: _saveAppointment,
          onChanged: _onFormChanged,
        );
      case AdoptionStep.appReview:
        return ApplicationReviewStep(
          form: _form,
          animalName: widget.animal.name,
          readOnly: _isReadOnly,
          isSubmitting: _isSubmitting,
          onPickDate: _pickDate,
          onWithdraw: _withdrawApplication,
        );
      case AdoptionStep.timeToMeet:
        return TimeToMeetStep(
          form: _form,
          animalName: widget.animal.name,
          readOnly: _isReadOnly,
          isSubmitting: _isSubmitting,
          isReservedForMe: _isReservedForMe,
          scheduledReleaseDate: _scheduledReleaseDate,
          deliveryAttempts: _deliveryAttempts,
          onWithdraw: _withdrawApplication,
          onRequestReschedule: _requestDeliveryReschedule,
        );
      case AdoptionStep.adoptionDay:
        return AdoptionDayStep(
          animalName: widget.animal.name,
          scheduledReleaseDate: _scheduledReleaseDate,
          deliveryAttempts: _deliveryAttempts,
        );
      case AdoptionStep.appReject:
        return ApplicationUpdateStep(animalName: widget.animal.name);
      case AdoptionStep.withdrawn:
        return WithdrawnStep(
          animalName: widget.animal.name,
          readOnly: _isReadOnly,
          onStartOver: _resetProcessState,
        );
    }
  }
}
