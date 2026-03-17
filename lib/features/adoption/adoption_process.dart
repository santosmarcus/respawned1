import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../app_theme.dart';
import 'adoption_page.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

enum _AdoptionProcess {
  intro,           // 1st step - Lets start
  bookAppointment, // 2nd step  – Book appointment
  appReview,       // 3rd step  – Application review
  timeToMeet,      // 4th step  – Appointment confirmed
  adoptionDay,     // 5th step  – Adoption Day! (success)
  appReject,       // 5th step  – Application Update (rejected)
}

const List<String> _stepLabels = [
  'Fill out adoption form',
  'Book appointment',
  'Application review',
  'Time to meet!',
  'Adoption Day',
];


class AdoptionProcess extends StatefulWidget {
  final Animal animal;
  const AdoptionProcess({super.key, required this.animal});
  @override
  State<AdoptionProcess> createState() => _AdoptionProcessState();
}


class _AdoptionProcessState extends State<AdoptionProcess> {
  _AdoptionProcess _step = _AdoptionProcess.intro;

  // Form fields
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _addressCtrl = TextEditingController();
  final _reasonCtrl = TextEditingController();

  String? _adoptionId;
  bool _isSubmitting = false;

  // Appointment
  DateTime? _appointmentDate;
  String _appointmentType = 'On-site Visit';
  String? _appointmentTime;

  // timeslots --- to be changed
  static const Map<int, List<String>> _timeSlots = {
    0: ['9:00 AM', '10:00 AM', '11:00 AM', '2:00 PM', '3:00 PM', '4:00 PM'],
    1: [
      '9:00 AM',
      '10:00 AM',
      '11:00 AM',
      '1:00 PM',
      '2:00 PM',
      '3:00 PM',
      '4:00 PM'
    ],
    2: ['10:00 AM', '11:00 AM', '2:00 PM', '3:00 PM'],
    3: ['9:00 AM', '10:00 AM', '11:00 AM', '1:00 PM', '3:00 PM', '4:00 PM'],
    4: ['9:00 AM', '10:00 AM', '2:00 PM', '3:00 PM', '4:00 PM'],
    5: ['10:00 AM', '11:00 AM', '12:00 PM'],
    6: [], // Sunday – closed
  };

  List<String> get _slotsForDate {
    if (_appointmentDate == null) return [];
    // weekday: 1=Mon … 7=Sun → convert to 0-based Mon-Sun
    final dow = (_appointmentDate!.weekday - 1) % 7;
    return _timeSlots[dow] ?? [];
  }

  @override
  void initState() {
    super.initState();
    _prefillFromAccount();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _phoneCtrl.dispose();
    _addressCtrl.dispose();
    _reasonCtrl.dispose();
    super.dispose();
  }

  int get _activeStepIndex {
    switch (_step) {
      case _AdoptionProcess.intro:
        return 0;
      case _AdoptionProcess.bookAppointment:
        return 1;
      case _AdoptionProcess.appReview:
        return 2;
      case _AdoptionProcess.timeToMeet:
        return 3;
      case _AdoptionProcess.adoptionDay:
        return 4;
      case _AdoptionProcess.appReject:
        return 2; // rejected stays at review
    }
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
    if (picked != null) setState(() => _appointmentDate = picked);
  }

  String _formatDate(DateTime d) =>
      '${_monthName(d.month)} ${d.day}, ${d.year}';

  String _monthName(int m) =>
      const [
        '', 'January', 'February', 'March', 'April', 'May', 'June',
        'July', 'August', 'September', 'October', 'November', 'December'
      ][m];


  //Firestore Helpers
  Future<void> _prefillFromAccount() async {
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) return;

      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .get();

      final data = doc.data();
      if (data == null) return;

      setState(() {
        _nameCtrl.text =
            '${data['firstName'] ?? ''} ${data['lastName'] ?? ''}'.trim();
        _phoneCtrl.text =
            data['phone'] ?? '';
        _addressCtrl.text =
            data['address'] ?? '';
        _emailCtrl.text =
            FirebaseAuth.instance.currentUser?.email ?? data['email'] ?? '';
      });
    } catch (_) {}
  }

  Future<void> _submitAdoptionForm() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _isSubmitting = true);

    try {
      final uid = FirebaseAuth.instance.currentUser!.uid;

      final docRef = await FirebaseFirestore.instance
          .collection('adoptions')
          .add({
        'adopterId': uid,
        'animalId': widget.animal.id, //--- to be changed---
        'animalName': widget.animal.name, //--- to be changed ---
        'adopterName': _nameCtrl.text.trim(),
        'adopterEmail': _emailCtrl.text.trim(),
        'adopterPhone': _phoneCtrl.text.trim(),
        'adopterAddress': _addressCtrl.text.trim(),
        'reason': _reasonCtrl.text.trim(),
        'status': 'pending_appointment', //--- to be changed when admin view is available---
        'statusHistory': [
          {
            'status': 'Form submitted.',
            'timestamp': Timestamp.now(),
          }
        ],
        'createdAt': FieldValue.serverTimestamp(),
      });

      setState(() {
        _adoptionId = docRef.id;
        _step = _AdoptionProcess.bookAppointment;
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
      await FirebaseFirestore.instance
          .collection('adoptions')
          .doc(_adoptionId).update({
        'appointmentType': _appointmentType,
        'appointmentDate': Timestamp.fromDate(_appointmentDate!),
        'appointmentTime': _appointmentTime,
        'status': 'under_review',
        'statusHistory': FieldValue.arrayUnion([{
          'status': 'Appointment booked.',
          'timestamp': Timestamp.now(),
        }
        ]),
      });

      setState(() => _step = _AdoptionProcess.appReview);
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

  Future<void> _updateStatus(String status,
      String statusMessage,
      _AdoptionProcess nextStep,) async {
    if (_adoptionId == null) return;
    setState(() => _isSubmitting = true);

    try {
      await FirebaseFirestore.instance
          .collection('adoptions')
          .doc(_adoptionId)
          .update({
        'status': status,
        'statusHistory': FieldValue.arrayUnion([
          {
            'status': statusMessage,
            'timestamp': Timestamp.now(),
          }
        ]),
      });

      setState(() => _step = nextStep);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
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
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: 0,
        items: const [
          BottomNavigationBarItem(
              icon: Icon(Icons.home_outlined),
              activeIcon: Icon(Icons.home),
              label: 'Home'),
          BottomNavigationBarItem(
              icon: Icon(Icons.notifications_outlined),
              activeIcon: Icon(Icons.notifications),
              label: 'Notifications'),
          BottomNavigationBarItem(
              icon: Icon(Icons.person_outline),
              activeIcon: Icon(Icons.person),
              label: 'My Profile'),
        ],
        onTap: (_) {},
      ),
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
                    child: const Icon(Icons.close,
                        size: 22, color: AppColors.textPrimary),
                  ),
                  const SizedBox(width: 16),
                  Text(
                    'Adopt ${widget.animal.name}',
                    style: GoogleFonts.tiltWarp(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            // Tracker
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: _StepTracker(
                labels: _stepLabels,
                activeIndex: _activeStepIndex,
                rejected: _step == _AdoptionProcess.appReject,
              ),
            ),

            const SizedBox(height: 24),

            // body
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: _buildStepBody(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // switcher
  Widget _buildStepBody() {
    switch (_step) {
      case _AdoptionProcess.intro:
        return _buildIntro();
      case _AdoptionProcess.bookAppointment:
        return _buildBookAppointment();
      case _AdoptionProcess.appReview:
        return _buildAppReview();
      case _AdoptionProcess.timeToMeet:
        return _buildTimeToMeet();
      case _AdoptionProcess.adoptionDay:
        return _buildAdoptionDay();
      case _AdoptionProcess.appReject:
        return _buildAppUpdate();
    }
  }

  // 1st step --- fill out form
  Widget _buildIntro() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Fill out adoption form',
          style: GoogleFonts.tiltWarp(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: AppColors.textPrimary),
        ),
        const SizedBox(height: 6),
        Text(
          'Ready to give a rescue a loving forever home?',
          style: GoogleFonts.zain(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary),
        ),
        const SizedBox(height: 4),
        Text(
          'Fill out this quick form to help us match you with the right rescue and confirm eligibility for adoption.',
          style: GoogleFonts.zain(
              fontSize: 14, color: AppColors.textSecondary, height: 1.5),
        ),

        const SizedBox(height: 24),

        // Form
        Form(
          key: _formKey,
          child: Column(
            children: [
              _FormField(controller: _nameCtrl,
                label: 'Full Name',
                hint: ' ',
                readOnly: true,),
              const SizedBox(height: 12),
              _FormField(controller: _emailCtrl,
                  label: 'Email',
                  hint: ' ',
                  readOnly: true,
                  keyboardType: TextInputType.emailAddress),
              const SizedBox(height: 12),
              _FormField(controller: _phoneCtrl,
                  label: 'Phone Number',
                  hint: ' ',
                  readOnly: true,
                  keyboardType: TextInputType.phone),
              const SizedBox(height: 12),
              _FormField(controller: _addressCtrl,
                  label: 'Home Address',
                  hint: ' ',),
              const SizedBox(height: 12),
              _FormField(
                controller: _reasonCtrl,
                label: 'Why do you want to adopt?',
                hint: 'Tell us a little about yourself…',
                maxLines: 4,
              ),
            ],
          ),
        ),

        const SizedBox(height: 28),

        _PrimaryButton(
          label: _isSubmitting ? 'Submitting...' : "Let's Start",
          onTap: _isSubmitting ? null : _submitAdoptionForm,
        ),

        const SizedBox(height: 24),
      ],
    );
  }

  // 2nd step --- book appointment
  Widget _buildBookAppointment() {
    final slots = _slotsForDate;
    final isSunday = _appointmentDate != null &&
        _appointmentDate!.weekday == DateTime.sunday;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Book appointment',
            style: GoogleFonts.tiltWarp(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: AppColors.textPrimary)),
        const SizedBox(height: 6),
        Text('Just a few steps more.',
            style: GoogleFonts.zain(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary)),
        const SizedBox(height: 4),
        Text(
          'As part of this process, we\'d like to schedule an interview with the organization to further assess suitability and answer any questions you may have.\n\nPlease choose a date that works best for you, and we\'ll confirm your appointment once your application has been reviewed.',
          style: GoogleFonts.zain(
              fontSize: 14, color: AppColors.textSecondary, height: 1.5),
        ),

        const SizedBox(height: 20),

        // visit type
        Row(
          children: ['On-site Visit', 'Online'].map((type) {
            final selected = _appointmentType == type;
            return GestureDetector(
              onTap: () => setState(() => _appointmentType = type),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                margin: const EdgeInsets.only(right: 10),
                padding:
                const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
                decoration: BoxDecoration(
                  color: selected
                      ? AppColors.greenrspwn
                      : AppColors.lavenderrspwn,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(type,
                    style: GoogleFonts.zain(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary)),
              ),
            );
          }).toList(),
        ),

        const SizedBox(height: 20),

        // calendar
        Container(
          decoration: BoxDecoration(
            color: AppColors.yellowrspwn.withOpacity(0.25),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.greenrspwn, width: 1.2),
          ),
          child: CalendarDatePicker(
            initialDate: _appointmentDate ??
                DateTime.now().add(const Duration(days: 1)),
            firstDate: DateTime.now().add(const Duration(days: 1)),
            lastDate: DateTime.now().add(const Duration(days: 90)),
            onDateChanged: (picked) {
              setState(() {
                _appointmentDate = picked;
                _appointmentTime = null;
              });
            },
          ),
        ),

        const SizedBox(height: 16),

        // time slot selection
        Text(
          'Available times',
          style: GoogleFonts.tiltWarp(
              fontSize: 13,
              fontWeight: FontWeight.bold,
              color: AppColors.textPrimary),
        ),
        const SizedBox(height: 8),

        if (_appointmentDate == null)
          Text('Select a date above to see available times.',
              style: GoogleFonts.zain(
                  fontSize: 13, color: AppColors.textSecondary))
        else
          if (isSunday || slots.isEmpty)
            Container(
              padding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: AppColors.slaterspwn.withOpacity(0.4),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                isSunday
                    ? 'Closed on Sundays — please pick another day.'
                    : 'No slots available for this date.',
                style: GoogleFonts.zain(
                    fontSize: 13, color: AppColors.textSecondary),
              ),
            )
          else
            SizedBox(
              height: 40,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: slots.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (context, i) {
                  final slot = slots[i];
                  final selected = _appointmentTime == slot;
                  return GestureDetector(
                    onTap: () => setState(() => _appointmentTime = slot),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 8),
                      decoration: BoxDecoration(
                        color: selected
                            ? AppColors.greenrspwn
                            : AppColors.background,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: selected
                              ? AppColors.greenrspwn
                              : AppColors.slaterspwn,
                          width: 1.2,
                        ),
                      ),
                      child: Text(
                        slot,
                        style: GoogleFonts.zain(
                          fontSize: 13,
                          fontWeight: selected
                              ? FontWeight.w700
                              : FontWeight.w500,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),

        // summary
        if (_appointmentDate != null && _appointmentTime != null) ...[
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.yellowrspwn.withOpacity(0.35),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                const Icon(Icons.event_available,
                    color: AppColors.greenrspwn, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '$_appointmentType  ·  ${_formatDate(
                        _appointmentDate!)}  ·  $_appointmentTime',
                    style: GoogleFonts.zain(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary),
                  ),
                ),
              ],
            ),
          ),
        ],

        const SizedBox(height: 28),

        _PrimaryButton(
          label: _isSubmitting ? 'Booking...' : 'Book',
          onTap: (_appointmentDate == null || _appointmentTime == null ||
              _isSubmitting)
              ? null
              : _saveAppointment,
        ),

        const SizedBox(height: 24),
      ],
    );
  }

  // 3rd step --- application review
  Widget _buildAppReview() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Application review',
          style: GoogleFonts.tiltWarp(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: AppColors.textPrimary),
        ),
        const SizedBox(height: 12),
        Text(
          'We\'ve received your interest in adopting ${widget.animal.name}.',
          style: GoogleFonts.zain(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary),
        ),
        const SizedBox(height: 4),
        Text(
          'Please allow us time to review your form and confirm your appointment. If you need to reschedule, kindly update your meeting date at least 3 days before your appointment.',
          style: GoogleFonts.zain(
              fontSize: 14, color: AppColors.textSecondary, height: 1.5),
        ),

        const SizedBox(height: 28),
        _PrimaryButton(
          label: 'Change date',
          onTap: _isSubmitting ? null : _pickDate,
        ),

        const SizedBox(height: 12),

        // ---------- for testing only!!
        Row(
          children: [
            Expanded(
              child: _SecondaryButton(
                label: 'Approved →',
                onTap: _isSubmitting
                    ? null
                    : () =>
                    _updateStatus('appointment_confirmed',
                      'Application approved. Appointment confirmed.',
                      _AdoptionProcess.timeToMeet,),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _SecondaryButton(
                label: 'Rejected →',
                onTap: _isSubmitting
                    ? null
                    : () =>
                    _updateStatus('rejected', 'Application was not approved.',
                      _AdoptionProcess.appReject,),
              ),
            ),
          ],
        ),
        // ---------- for testing only ^^^^

        const SizedBox(height: 24),
      ],
    );
  }

  // 4th step --- meeting
  Widget _buildTimeToMeet() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Time to meet!',
          style: GoogleFonts.tiltWarp(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: AppColors.textPrimary),
        ),
        const SizedBox(height: 12),
        Text(
          'Your adoption application and interview appointment have been confirmed! We are excited to get to know you as a potential adopter for ${widget
              .animal.name} for today!',
          style: GoogleFonts.zain(
              fontSize: 14, color: AppColors.textSecondary, height: 1.5),
        ),

        if (_appointmentDate != null) ...[
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.yellowrspwn.withOpacity(0.35),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                const Icon(Icons.event_available,
                    color: AppColors.greenrspwn, size: 20),
                const SizedBox(width: 10),
                Text(
                  '${_appointmentType}  ·  ${_formatDate(_appointmentDate!)}',
                  style: GoogleFonts.zain(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary),
                ),
              ],
            ),
          ),
        ],

        const SizedBox(height: 28),

        _PrimaryButton(
          label: _isSubmitting ? 'Updating...' : 'Adoption Day!',
          onTap: _isSubmitting
              ? null
              : () =>
              _updateStatus('completed', 'Adoption Completed!',
                _AdoptionProcess.adoptionDay,),
        ),

        const SizedBox(height: 24),
      ],
    );
  }

  // 5th step -- adoption success
  Widget _buildAdoptionDay() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Adoption Day!',
          style: GoogleFonts.tiltWarp(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: AppColors.textPrimary),
        ),
        const SizedBox(height: 12),
        Text(
          'Congratulations on your new furry companion!',
          style: GoogleFonts.zain(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary),
        ),
        const SizedBox(height: 6),
        Text(
          'The organization will safely deliver your pet to your generalhome. You\'ll also receive an adoption agreement outlining terms and conditions, post-adoption guidelines, and return policies.\n\nWe\'re so happy for you and your new best friend!',
          style: GoogleFonts.zain(
              fontSize: 14, color: AppColors.textSecondary, height: 1.5),
        ),

        const SizedBox(height: 28),

        _PrimaryButton(
          label: 'Close',
          onTap: () {
            // Pop back to root (adoption list)
            Navigator.popUntil(context, (route) => route.isFirst);
          },
        ),

        const SizedBox(height: 24),
      ],
    );
  }

  // 5th step --- adoption failed
  Widget _buildAppUpdate() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Application Update',
          style: GoogleFonts.tiltWarp(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: AppColors.textPrimary),
        ),
        const SizedBox(height: 12),
        Text(
          'Thank you for your interest in adopting ${widget.animal.name}.',
          style: GoogleFonts.zain(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary),
        ),
        const SizedBox(height: 6),
        Text(
          'After careful review, we feel this may not be the best match at this time.\n\nWe truly appreciate your willingness to give a rescue a loving generalhome, and we encourage you to consider other pets in need — your perfect companion could be waiting!',
          style: GoogleFonts.zain(
              fontSize: 14, color: AppColors.textSecondary, height: 1.5),
        ),

        const SizedBox(height: 28),

        _PrimaryButton(
          label: 'Close',
          onTap: () => Navigator.popUntil(context, (route) => route.isFirst),
        ),

        const SizedBox(height: 24),
      ],
    );
  }
}

// Step tracker widget
class _StepTracker extends StatelessWidget {
  final List<String> labels;
  final int activeIndex;
  final bool rejected;

  const _StepTracker({
    required this.labels,
    required this.activeIndex,
    this.rejected = false,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: List.generate(labels.length, (i) {
        final isDone = i < activeIndex;
        final isActive = i == activeIndex;
        final isRejected = rejected && i == activeIndex;

        Color dotColor;
        if (isRejected) {
          dotColor = Colors.redAccent;
        } else if (isDone) {
          dotColor = AppColors.lavenderrspwn;
        } else if (isActive) {
          dotColor = AppColors.lavenderrspwn;
        } else {
          dotColor = AppColors.slaterspwn;
        }

        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Dot + vertical line
            Column(
              children: [
                Container(
                  width: 14,
                  height: 14,
                  decoration: BoxDecoration(
                    color: dotColor,
                    shape: BoxShape.circle,
                    border: isActive
                        ? Border.all(color: AppColors.textPrimary, width: 2)
                        : null,
                  ),
                  child: isDone
                      ? const Icon(Icons.check, size: 9, color: AppColors.textPrimary)
                      : null,
                ),
                if (i < labels.length - 1)
                  Container(
                    width: 2,
                    height: 28,
                    color: i < activeIndex
                        ? AppColors.greenrspwn
                        : AppColors.slaterspwn,
                  ),
              ],
            ),

            const SizedBox(width: 12),

            Padding(
              padding: const EdgeInsets.only(top: 0),
              child: Text(
                labels[i],
                style: GoogleFonts.zain(
                  fontSize: 14,
                  fontWeight:
                  isActive ? FontWeight.w700 : FontWeight.w500,
                  color: isActive
                      ? AppColors.textPrimary
                      : AppColors.textSecondary,
                ),
              ),
            ),
          ],
        );
      }),
    );
  }
}

// Reusable form field
class _FormField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final String hint;
  final TextInputType keyboardType;
  final int maxLines;
  final bool readOnly;

  const _FormField({
    required this.controller,
    required this.label,
    required this.hint,
    this.keyboardType = TextInputType.text,
    this.maxLines = 1,
    this.readOnly = false,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: GoogleFonts.zain(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: AppColors.textSecondary,
          ),
        ),
        const SizedBox(height: 4),
        TextFormField(
          controller: controller,
          keyboardType: keyboardType,
          maxLines: maxLines,
          readOnly: readOnly,
          style: GoogleFonts.zain(fontSize: 15, color: AppColors.textPrimary),
          validator: (v) =>
          (v == null || v.trim().isEmpty) ? 'This field is required' : null,
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: GoogleFonts.zain(
                fontSize: 14, color: AppColors.textSecondary),
            filled: true,
            fillColor: readOnly
            ? AppColors.slaterspwn.withOpacity(0.3) : AppColors.yellowrspwn.withOpacity(0.3),
            contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide:
              BorderSide(color: AppColors.slaterspwn, width: 1),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide:
              const BorderSide(color: AppColors.greenrspwn, width: 1.5),
            ),
            errorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide:
              const BorderSide(color: Colors.redAccent, width: 1.2),
            ),
            focusedErrorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide:
              const BorderSide(color: Colors.redAccent, width: 1.5),
            ),
          ),
        ),
      ],
    );
  }
}


// buttons

class _PrimaryButton extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;

  const _PrimaryButton({required this.label, this.onTap});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 50,
      child: ElevatedButton(
        onPressed: onTap,
        style: ElevatedButton.styleFrom(
          backgroundColor:
          onTap == null ? AppColors.slaterspwn : AppColors.yellowrspwn,
          foregroundColor: AppColors.textPrimary,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(30),
          ),
        ),
        child: Text(
          label,
          style: GoogleFonts.tiltWarp(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: AppColors.textPrimary,
          ),
        ),
      ),
    );
  }
}

class _SecondaryButton extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;

  const _SecondaryButton({required this.label, this.onTap});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 44,
      child: OutlinedButton(
        onPressed: onTap,
        style: OutlinedButton.styleFrom(
          side: const BorderSide(color: AppColors.greenrspwn, width: 1.5),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
        child: Text(
          label,
          style: GoogleFonts.zain(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: AppColors.textPrimary,
          ),
        ),
      ),
    );
  }
}