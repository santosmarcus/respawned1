import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:respawnd1/app_theme.dart';
import 'intake_detail_page.dart';

class TreatmentDetailPage extends StatefulWidget {
  final String caseId;
  final Map<String, dynamic> data;
  const TreatmentDetailPage(
      {super.key, required this.caseId, required this.data});

  @override
  State<TreatmentDetailPage> createState() => _TreatmentDetailPageState();
}

class _TreatmentDetailPageState extends State<TreatmentDetailPage> {
  bool _showAllLogs = false;
  bool _showUpdateForm = false;
  bool _isDeceased = false;
  bool _isLoading = false;

  // Form state
  final _notesController = TextEditingController();
  final _medicationController = TextEditingController();
  String? _selectedUpdateType;
  String? _selectedCondition;
  String? _selectedCauseOfDeath;
  DateTime? _updateDateTime;

  final List<String> _updateTypes = [
    'Initial Assessment',
    'Medication',
    'Procedure',
    'Wound Care',
    'Vaccination',
    'Follow-up Check',
    'Discharge Ready',
    'Death Report',
  ];

  final List<String> _conditions = [
    'Critical',
    'Stable',
    'Recovering',
    'Ready for Discharge',
    'Deceased',
  ];

  final List<String> _causesOfDeath = [
    'Infection',
    'Trauma/Injury',
    'Disease',
    'Treatment Complications',
    'Malnutrition',
    'Other:',
  ];

  @override
  void dispose() {
    _notesController.dispose();
    _medicationController.dispose();
    super.dispose();
  }

  Future<void> _addUpdate() async {
    if (_selectedUpdateType == null ||
        _selectedCondition == null ||
        _notesController.text.trim().isEmpty) return;

    setState(() => _isLoading = true);

    final entry = {
      'type': _selectedUpdateType,
      'notes': _notesController.text.trim(),
      'condition': _selectedCondition,
      'medicationGiven': _medicationController.text.trim(),
      'timestamp': Timestamp.now(),
      'addedBy': 'Admin Staff',
      if (_isDeceased) 'causeOfDeath': _selectedCauseOfDeath,
    };

    await FirebaseFirestore.instance
        .collection('cases')
        .doc(widget.caseId)
        .update({
      'currentCondition': _selectedCondition,
      'treatmentLog': FieldValue.arrayUnion([entry]),
      'statusHistory': FieldValue.arrayUnion([
        {
          'status': '${_selectedUpdateType}: ${_notesController.text.trim()}',
          'timestamp': Timestamp.now(),
        }
      ]),
      if (_isDeceased) 'animalStatus': 'Deceased',
    });

    if (mounted) {
      setState(() {
        _showUpdateForm = false;
        _isDeceased = false;
        _selectedUpdateType = null;
        _selectedCondition = null;
        _notesController.clear();
        _medicationController.clear();
        _isLoading = false;
      });
    }
  }

  Future<void> _closeCase() async {
    await FirebaseFirestore.instance
        .collection('cases')
        .doc(widget.caseId)
        .update({
      'status': 'closed',
      'statusHistory': FieldValue.arrayUnion([
        {'status': 'Case closed. Animal deceased.', 'timestamp': Timestamp.now()}
      ]),
    });
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance
          .collection('cases')
          .doc(widget.caseId)
          .snapshots(),
      builder: (context, snapshot) {
        final data = snapshot.hasData
            ? (snapshot.data!.data() as Map<String, dynamic>? ?? widget.data)
            : widget.data;

        final treatmentLog = List<Map<String, dynamic>>.from(
            data['treatmentLog'] ?? []).reversed.toList();
        final isDeceased = data['animalStatus'] == 'Deceased';
        final urgency = data['urgency'] ?? '';

        final dateAdmitted = data['dateAdmitted'] as Timestamp?;
        final dateStr = dateAdmitted != null
            ? 'March ${dateAdmitted.toDate().day}, ${dateAdmitted.toDate().year}'
            : '-';

        int daysInTreatment = 0;
        if (dateAdmitted != null) {
          daysInTreatment =
              DateTime.now().difference(dateAdmitted.toDate()).inDays + 1;
        }

        return Scaffold(
          backgroundColor: AppColors.background,
          appBar: AppBar(
            backgroundColor: AppColors.textPrimary,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back, color: AppColors.background),
              onPressed: () => Navigator.pop(context),
            ),
            title: Text('Treatment Details',
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
                        Text(data['animalType'] ?? 'Animal',
                            style: GoogleFonts.tiltWarp(
                                fontSize: 24, color: AppColors.textPrimary)),
                        Text(
                            'CASE ID: ${widget.caseId.substring(0, 5).toUpperCase()}',
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

                // Info grid
                Row(
                  children: [
                    Expanded(
                      child: _InfoItem('Vet Clinic Name',
                          data['vetClinicName'] ?? '-'),
                    ),
                    Expanded(
                      child: _InfoItem(
                          'Days in Treatment', '$daysInTreatment'),
                    ),
                  ],
                ),
                Row(
                  children: [
                    Expanded(
                        child: _InfoItem('Date Admitted', dateStr)),
                    Expanded(
                        child: _InfoItem('Animal Status',
                            data['currentCondition'] ?? '-')),
                  ],
                ),

                const SizedBox(height: 16),

                // Treatment Logs
                Text('Treatment Logs',
                    style: GoogleFonts.tiltWarp(
                        fontSize: 15, color: AppColors.textPrimary)),

                const SizedBox(height: 8),

                if (treatmentLog.isEmpty)
                  Text('No treatment logs yet.',
                      style: GoogleFonts.zain(
                          fontSize: 13, color: AppColors.textSecondary))
                else ...[
                  ...( _showAllLogs
                      ? treatmentLog
                      : treatmentLog.take(2).toList())
                      .map((log) => _TreatmentLogCard(log: log)),
                  if (treatmentLog.length > 2)
                    Center(
                      child: GestureDetector(
                        onTap: () =>
                            setState(() => _showAllLogs = !_showAllLogs),
                        child: Container(
                          padding: const EdgeInsets.all(8),
                          child: Icon(
                            _showAllLogs
                                ? Icons.keyboard_arrow_up
                                : Icons.keyboard_arrow_down,
                            color: AppColors.textPrimary,
                          ),
                        ),
                      ),
                    ),
                ],

                const SizedBox(height: 24),

                // Update form
                if (_showUpdateForm) ...[
                  Text('Enter Treatment Update',
                      style: GoogleFonts.tiltWarp(
                          fontSize: 16, color: AppColors.textPrimary),
                      textAlign: TextAlign.center),

                  const SizedBox(height: 16),

                  // Date & Time
                  _FieldLabel('Date & Time', required: true),
                  GestureDetector(
                    onTap: () async {
                      final now = DateTime.now();
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: now,
                        firstDate: DateTime(2020),
                        lastDate: now,
                      );
                      if (picked != null)
                        setState(() => _updateDateTime = picked);
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 12),
                      decoration: BoxDecoration(
                        border: const Border(
                            bottom: BorderSide(color: AppColors.textPrimary)),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            _updateDateTime == null
                                ? 'mm/dd/yyyy hh:mm'
                                : '${_updateDateTime!.month}/${_updateDateTime!.day}/${_updateDateTime!.year}',
                            style: GoogleFonts.zain(
                                fontSize: 14,
                                color: _updateDateTime == null
                                    ? AppColors.textSecondary
                                    : AppColors.textPrimary),
                          ),
                          const Icon(Icons.calendar_today_outlined,
                              size: 18, color: AppColors.textPrimary),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 16),

                  // Update Type
                  _FieldLabel('Update Type', required: true),
                  _Dropdown(
                    value: _selectedUpdateType,
                    hint: 'Select',
                    items: _updateTypes,
                    onChanged: (val) {
                      setState(() {
                        _selectedUpdateType = val;
                        _isDeceased = val == 'Death Report';
                        if (_isDeceased) _selectedCondition = 'Deceased';
                      });
                    },
                  ),

                  const SizedBox(height: 16),

                  if (_isDeceased) ...[
                    // Cause of death
                    _FieldLabel('Cause of Death', required: true),
                    _Dropdown(
                      value: _selectedCauseOfDeath,
                      hint: 'Select',
                      items: _causesOfDeath,
                      onChanged: (val) =>
                          setState(() => _selectedCauseOfDeath = val),
                    ),
                  ] else ...[
                    // Overall Condition
                    _FieldLabel('Overall Condition', required: true),
                    _Dropdown(
                      value: _selectedCondition,
                      hint: 'Select',
                      items: _conditions,
                      onChanged: (val) =>
                          setState(() => _selectedCondition = val),
                    ),
                  ],

                  const SizedBox(height: 16),

                  // Notes
                  _FieldLabel('Notes', required: true),
                  TextField(
                    controller: _notesController,
                    decoration: InputDecoration(
                      hintText: 'Enter notes',
                      hintStyle: GoogleFonts.zain(
                          color: AppColors.textSecondary, fontSize: 14),
                      enabledBorder: const UnderlineInputBorder(
                        borderSide:
                        BorderSide(color: AppColors.textPrimary),
                      ),
                      focusedBorder: const UnderlineInputBorder(
                        borderSide: BorderSide(
                            color: AppColors.textPrimary, width: 1.5),
                      ),
                      isDense: true,
                      contentPadding: const EdgeInsets.only(bottom: 8),
                    ),
                    style: GoogleFonts.zain(
                        fontSize: 14, color: AppColors.textPrimary),
                  ),

                  if (!_isDeceased) ...[
                    const SizedBox(height: 16),
                    _FieldLabel('Medication Given'),
                    TextField(
                      controller: _medicationController,
                      decoration: InputDecoration(
                        hintText: 'Enter notes',
                        hintStyle: GoogleFonts.zain(
                            color: AppColors.textSecondary, fontSize: 14),
                        enabledBorder: const UnderlineInputBorder(
                          borderSide:
                          BorderSide(color: AppColors.textPrimary),
                        ),
                        focusedBorder: const UnderlineInputBorder(
                          borderSide: BorderSide(
                              color: AppColors.textPrimary, width: 1.5),
                        ),
                        isDense: true,
                        contentPadding: const EdgeInsets.only(bottom: 8),
                      ),
                      style: GoogleFonts.zain(
                          fontSize: 14, color: AppColors.textPrimary),
                    ),
                  ],

                  const SizedBox(height: 16),

                  // Media
                  _FieldLabel('Include images and videos'),
                  const SizedBox(height: 8),
                  Container(
                    width: 80, height: 80,
                    decoration: BoxDecoration(
                      border: Border.all(
                          color: AppColors.greenrspwn,
                          style: BorderStyle.solid,
                          width: 1.5),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Center(
                      child: Icon(Icons.add,
                          size: 28, color: AppColors.greenrspwn),
                    ),
                  ),

                  const SizedBox(height: 24),

                  // Add button
                  Center(
                    child: ElevatedButton(
                      onPressed: _isLoading ? null : _addUpdate,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.yellowrspwn,
                        fixedSize: Size(
                            MediaQuery.of(context).size.width * 0.5, 48),
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(30)),
                      ),
                      child: _isLoading
                          ? const SizedBox(
                          height: 20, width: 20,
                          child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: AppColors.textPrimary))
                          : Text('Add',
                          style: GoogleFonts.tiltWarp(
                              fontSize: 16,
                              color: AppColors.textPrimary)),
                    ),
                  ),
                ],

                const SizedBox(height: 32),

                // Bottom action buttons
                if (isDeceased)
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _closeCase,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.yellowrspwn,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(30)),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      child: Text('Close Case',
                          style: GoogleFonts.tiltWarp(
                              fontSize: 16, color: AppColors.textPrimary)),
                    ),
                  )
                else
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => IntakeDetailPage(
                                  caseId: widget.caseId, data: data),
                            ),
                          ),
                          style: OutlinedButton.styleFrom(
                            side: const BorderSide(
                                color: AppColors.textPrimary),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(30)),
                            padding:
                            const EdgeInsets.symmetric(vertical: 14),
                          ),
                          child: Text('Intake',
                              style: GoogleFonts.tiltWarp(
                                  fontSize: 15,
                                  color: AppColors.textPrimary)),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: () =>
                              setState(() => _showUpdateForm = !_showUpdateForm),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.yellowrspwn,
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(30)),
                            padding:
                            const EdgeInsets.symmetric(vertical: 14),
                          ),
                          child: Text(
                            _showUpdateForm ? 'Hide Form' : 'Add Update',
                            style: GoogleFonts.tiltWarp(
                                fontSize: 15, color: AppColors.textPrimary),
                          ),
                        ),
                      ),
                    ],
                  ),

                const SizedBox(height: 32),
              ],
            ),
          ),
        );
      },
    );
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

class _FieldLabel extends StatelessWidget {
  final String label;
  final bool required;
  const _FieldLabel(this.label, {this.required = false});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(label,
            style: GoogleFonts.zain(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary)),
        if (required)
          const Text(' *',
              style: TextStyle(color: Colors.red, fontSize: 14)),
      ],
    );
  }
}

class _Dropdown extends StatelessWidget {
  final String? value;
  final String hint;
  final List<String> items;
  final Function(String?) onChanged;

  const _Dropdown({
    required this.value,
    required this.hint,
    required this.items,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<String>(
      value: value,
      hint: Text(hint,
          style: GoogleFonts.zain(
              fontSize: 14, color: AppColors.textSecondary)),
      style: GoogleFonts.zain(fontSize: 14, color: AppColors.textPrimary),
      decoration: const InputDecoration(
        isDense: true,
        contentPadding: EdgeInsets.only(bottom: 8),
        enabledBorder: UnderlineInputBorder(
          borderSide: BorderSide(color: AppColors.textPrimary),
        ),
        focusedBorder: UnderlineInputBorder(
          borderSide: BorderSide(color: AppColors.textPrimary, width: 1.5),
        ),
      ),
      items: items
          .map((item) => DropdownMenuItem(
        value: item,
        child: Text(item,
            style: GoogleFonts.zain(
                fontSize: 14, color: AppColors.textPrimary)),
      ))
          .toList(),
      onChanged: onChanged,
    );
  }
}