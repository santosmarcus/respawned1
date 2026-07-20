import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:respawnd1/app_theme.dart';
import 'package:respawnd1/core/utils/case_id.dart';

class IntakeDetailPage extends StatefulWidget {
  final String caseId;
  final Map<String, dynamic> data;
  const IntakeDetailPage(
      {super.key, required this.caseId, required this.data});

  @override
  State<IntakeDetailPage> createState() => _IntakeDetailPageState();
}

class _IntakeDetailPageState extends State<IntakeDetailPage> {
  bool _showAllLogs = false;
  bool _isLoading = false;

  // Intake form
  final _intakeStaffController = TextEditingController();
  final _otherNotesController = TextEditingController();
  String? _selectedShelter;
  DateTime? _intakeDate;

  final List<String> _shelterLocations = [
    'Dasmarinas, Cavite',
    'Pasay, Metro Manila',
    'Makati, Metro Manila',
    'Taguig, Metro Manila',
  ];

  @override
  void dispose() {
    _intakeStaffController.dispose();
    _otherNotesController.dispose();
    super.dispose();
  }

  Future<void> _createAnimalRecord() async {
    if (_selectedShelter == null || _intakeDate == null ||
        _intakeStaffController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please fill in all intake details.'),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final d = widget.data;

      // Create animal record
      final animalRef = await FirebaseFirestore.instance
          .collection('animals')
          .add({
        'species': d['animalType'] ?? '',
        'name': '',
        'breed': '',
        'sex': '',
        'age': 0,
        'status': 'intake',
        'adoptionStatus': 'not_ready',
        'shelterLocation': _selectedShelter,
        'intakeDate': Timestamp.fromDate(_intakeDate!),
        'intakeStaffName': _intakeStaffController.text.trim(),
        'intakeNotes': _otherNotesController.text.trim(),
        'vetClinicName': d['vetClinicName'] ?? '',
        'treatmentLog': d['treatmentLog'] ?? [],
        'linkedCaseId': widget.caseId,
        'reporterName': d['reporterName'] ?? '',
        'reporterPhone': d['reporterPhone'] ?? '',
        'transporterName': d['assignedVolunteerName'] ?? '',
        'condition': d['currentCondition'] ?? '',
        'photoUrls': d['photoUrls'] ?? [],
        'createdAt': FieldValue.serverTimestamp(),
      });

      // Update case
      await FirebaseFirestore.instance
          .collection('cases')
          .doc(widget.caseId)
          .update({
        'status': 'intake',
        'linkedAnimalId': animalRef.id,
        'statusHistory': FieldValue.arrayUnion([
          {
            'status': 'Animal has been admitted to the shelter.',
            'timestamp': Timestamp.now(),
          }
        ]),
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Animal record created successfully!'),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.pop(context);
        Navigator.pop(context);
      }
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
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.data;
    final urgency = d['urgency'] ?? '';
    final treatmentLog = List<Map<String, dynamic>>.from(
        d['treatmentLog'] ?? []).reversed.toList();

    // Get latest treatment log for discharge info
    final latestLog = treatmentLog.isNotEmpty ? treatmentLog.first : null;
    final dateAdmitted = d['dateAdmitted'] as Timestamp?;
    final dateDischargedStr = latestLog != null
        ? _formatTs(latestLog['timestamp'] as Timestamp?)
        : 'mm/dd/yyyy';

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.textPrimary,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppColors.background),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text('Intake Details',
            style: GoogleFonts.tiltWarp(
                fontSize: 18, color: AppColors.background)),
        actions: [
          IconButton(
            icon: const Icon(Icons.notifications_outlined,
                color: AppColors.background),
            onPressed: () {},
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(d['animalType'] ?? 'Animal',
                        style: GoogleFonts.tiltWarp(
                            fontSize: 24, color: AppColors.textPrimary)),
                    Text(
                        'CASE ID: ${shortCaseId(widget.caseId)}',
                        style: GoogleFonts.zain(
                            fontSize: 12, color: AppColors.textSecondary)),
                  ],
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 5),
                  decoration: BoxDecoration(
                    color: urgency == 'Critical'
                        ? Colors.red
                        : AppColors.yellowrspwn,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(urgency,
                      style: GoogleFonts.zain(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: Colors.white)),
                ),
              ],
            ),

            const SizedBox(height: 16),

            // Case info pulled from treatment/case data
            Row(
              children: [
                Expanded(
                    child: _InfoItem('Vet Clinic Name',
                        d['vetClinicName'] ?? '-')),
                Expanded(
                    child: _InfoItem('Date Discharged', dateDischargedStr)),
              ],
            ),
            Row(
              children: [
                Expanded(
                    child: _InfoItem('Condition at Discharge',
                        latestLog?['condition'] ?? d['currentCondition'] ?? '-')),
                Expanded(
                    child: _InfoItem(
                        'Transported by', d['assignedVolunteerName'] ?? '-')),
              ],
            ),
            _InfoItem('Reported by', d['reporterName'] ?? '-'),

            const SizedBox(height: 16),

            // Treatment Logs
            Text('Treatment Logs',
                style: GoogleFonts.tiltWarp(
                    fontSize: 15, color: AppColors.textPrimary)),

            const SizedBox(height: 8),

            if (treatmentLog.isEmpty)
              Text('No treatment logs.',
                  style: GoogleFonts.zain(
                      fontSize: 13, color: AppColors.textSecondary))
            else ...[
              ...(_showAllLogs
                  ? treatmentLog
                  : treatmentLog.take(2).toList())
                  .map((log) => _TreatmentLogCard(log: log)),
              if (treatmentLog.length > 2)
                Center(
                  child: GestureDetector(
                    onTap: () =>
                        setState(() => _showAllLogs = !_showAllLogs),
                    child: Icon(
                      _showAllLogs
                          ? Icons.keyboard_arrow_up
                          : Icons.keyboard_arrow_down,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
            ],

            const SizedBox(height: 24),

            // Intake Notes section
            Text('Intake Notes',
                style: GoogleFonts.tiltWarp(
                    fontSize: 15, color: AppColors.textPrimary)),

            const SizedBox(height: 12),

            // Shelter location + date
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Shelter Location',
                          style: GoogleFonts.zain(
                              fontSize: 12, color: AppColors.textSecondary)),
                      DropdownButtonFormField<String>(
                        value: _selectedShelter,
                        hint: Text('Select',
                            style: GoogleFonts.zain(
                                fontSize: 14,
                                color: AppColors.textSecondary)),
                        style: GoogleFonts.zain(
                            fontSize: 14, color: AppColors.textPrimary),
                        decoration: const InputDecoration(
                          isDense: true,
                          contentPadding: EdgeInsets.only(bottom: 4),
                          enabledBorder: UnderlineInputBorder(
                            borderSide:
                            BorderSide(color: AppColors.textPrimary),
                          ),
                          focusedBorder: UnderlineInputBorder(
                            borderSide: BorderSide(
                                color: AppColors.textPrimary, width: 1.5),
                          ),
                        ),
                        items: _shelterLocations
                            .map((s) => DropdownMenuItem(
                            value: s,
                            child: Text(s,
                                style: GoogleFonts.zain(fontSize: 14))))
                            .toList(),
                        onChanged: (val) =>
                            setState(() => _selectedShelter = val),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Date of Intake',
                          style: GoogleFonts.zain(
                              fontSize: 12, color: AppColors.textSecondary)),
                      GestureDetector(
                        onTap: () async {
                          final picked = await showDatePicker(
                            context: context,
                            initialDate: DateTime.now(),
                            firstDate: DateTime(2020),
                            lastDate: DateTime.now(),
                          );
                          if (picked != null)
                            setState(() => _intakeDate = picked);
                        },
                        child: Container(
                          padding: const EdgeInsets.only(bottom: 4),
                          decoration: const BoxDecoration(
                            border: Border(
                                bottom: BorderSide(
                                    color: AppColors.textPrimary)),
                          ),
                          child: Row(
                            mainAxisAlignment:
                            MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                _intakeDate == null
                                    ? 'mm/dd/yyyy'
                                    : '${_intakeDate!.month}/${_intakeDate!.day}/${_intakeDate!.year}',
                                style: GoogleFonts.zain(
                                    fontSize: 14,
                                    color: _intakeDate == null
                                        ? AppColors.textSecondary
                                        : AppColors.textPrimary),
                              ),
                              const Icon(Icons.calendar_today_outlined,
                                  size: 16, color: AppColors.textPrimary),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),

            const SizedBox(height: 16),

            // Intake staff name
            Text('Intake Staff Name',
                style: GoogleFonts.zain(
                    fontSize: 12, color: AppColors.textSecondary)),
            TextField(
              controller: _intakeStaffController,
              decoration: InputDecoration(
                hintText: 'Enter staff name',
                hintStyle: GoogleFonts.zain(
                    color: AppColors.textSecondary, fontSize: 14),
                isDense: true,
                contentPadding: const EdgeInsets.only(bottom: 8),
                enabledBorder: const UnderlineInputBorder(
                  borderSide: BorderSide(color: AppColors.textPrimary),
                ),
                focusedBorder: const UnderlineInputBorder(
                  borderSide:
                  BorderSide(color: AppColors.textPrimary, width: 1.5),
                ),
              ),
              style: GoogleFonts.zain(
                  fontSize: 14, color: AppColors.textPrimary),
            ),

            const SizedBox(height: 16),

            // Other notes
            Text('Other Notes',
                style: GoogleFonts.zain(
                    fontSize: 12, color: AppColors.textSecondary)),
            TextField(
              controller: _otherNotesController,
              decoration: InputDecoration(
                hintText: 'Enter notes',
                hintStyle: GoogleFonts.zain(
                    color: AppColors.textSecondary, fontSize: 14),
                isDense: true,
                contentPadding: const EdgeInsets.only(bottom: 8),
                enabledBorder: const UnderlineInputBorder(
                  borderSide: BorderSide(color: AppColors.textPrimary),
                ),
                focusedBorder: const UnderlineInputBorder(
                  borderSide:
                  BorderSide(color: AppColors.textPrimary, width: 1.5),
                ),
              ),
              style: GoogleFonts.zain(
                  fontSize: 14, color: AppColors.textPrimary),
            ),

            const SizedBox(height: 32),

            // Create Animal Record button
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _isLoading ? null : _createAnimalRecord,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.yellowrspwn,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(30)),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                child: _isLoading
                    ? const SizedBox(
                    height: 22, width: 22,
                    child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        color: AppColors.textPrimary))
                    : Text('Create Animal Record',
                    style: GoogleFonts.tiltWarp(
                        fontSize: 16, color: AppColors.textPrimary)),
              ),
            ),

            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  String _formatTs(Timestamp? ts) {
    if (ts == null) return '-';
    final d = ts.toDate();
    return '${d.month}/${d.day}/${d.year}';
  }
}

class _TreatmentLogCard extends StatelessWidget {
  final Map<String, dynamic> log;
  const _TreatmentLogCard({required this.log});

  @override
  Widget build(BuildContext context) {
    final ts = log['timestamp'] as Timestamp?;
    final timeStr = ts != null
        ? '${ts.toDate().hour.toString().padLeft(2, '0')}:${ts.toDate().minute.toString().padLeft(2, '0')} ${ts.toDate().hour >= 12 ? 'PM' : 'AM'}'
        : '';
    final dateStr = ts != null
        ? 'March ${ts.toDate().day}, ${ts.toDate().year}'
        : '';

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.tearspwn.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40, height: 40,
            decoration: BoxDecoration(
              color: AppColors.tearspwn,
              borderRadius: BorderRadius.circular(8),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(log['type'] ?? '',
                    style: GoogleFonts.zain(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary)),
                Text(log['notes'] ?? '',
                    style: GoogleFonts.zain(
                        fontSize: 12, color: AppColors.textSecondary)),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(log['condition'] ?? '',
                  style: GoogleFonts.zain(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary)),
              Text(timeStr,
                  style: GoogleFonts.zain(
                      fontSize: 10, color: AppColors.textSecondary)),
              Text(dateStr,
                  style: GoogleFonts.zain(
                      fontSize: 10, color: AppColors.textSecondary)),
            ],
          ),
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
          Text(label,
              style: GoogleFonts.zain(
                  fontSize: 12, color: AppColors.textSecondary)),
          Text(value,
              style: GoogleFonts.zain(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary)),
        ],
      ),
    );
  }
}