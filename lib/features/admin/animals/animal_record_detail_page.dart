import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:respawnd1/app_theme.dart';

class AnimalRecordDetailPage extends StatefulWidget {
  final String animalId;
  final Map<String, dynamic> data;

  const AnimalRecordDetailPage({
    super.key,
    required this.animalId,
    required this.data,
  });

  @override
  State<AnimalRecordDetailPage> createState() =>
      _AnimalRecordDetailPageState();
}

class _AnimalRecordDetailPageState extends State<AnimalRecordDetailPage> {
  int _tabIndex = 0; // 0=Overview, 1=Care, 2=Admin
  bool _showAllLogs = false;
  bool _inTreatment = false;
  bool _showAdmitForm = false;
  bool _showUpdateForm = false;
  bool _isLoading = false;

  // Admit form
  final _clinicNameController = TextEditingController();
  DateTime? _admitDate;

  // Update form fields (same as treatment detail)
  final _updateNotesController = TextEditingController();
  final _medicationController = TextEditingController();
  String? _selectedUpdateType;
  String? _selectedCondition;

  final List<String> _updateTypes = [
    'Initial Assessment', 'Medication', 'Procedure',
    'Wound Care', 'Vaccination', 'Follow-up Check',
    'Discharge Ready', 'Death Report',
  ];
  final List<String> _conditions = [
    'Critical', 'Stable', 'Recovering',
    'Ready for Discharge', 'Deceased',
  ];

  @override
  void dispose() {
    _clinicNameController.dispose();
    _updateNotesController.dispose();
    _medicationController.dispose();
    super.dispose();
  }

  Future<void> _admit() async {
    if (_clinicNameController.text.trim().isEmpty || _admitDate == null) return;
    setState(() => _isLoading = true);
    await FirebaseFirestore.instance
        .collection('animals')
        .doc(widget.animalId)
        .update({
      'vetClinicName': _clinicNameController.text.trim(),
      'dateAdmitted': Timestamp.fromDate(_admitDate!),
      'adoptionStatus': 'in_treatment',
      'currentCondition': 'Stable',
    });
    if (mounted) setState(() {
      _inTreatment = true;
      _showAdmitForm = false;
      _isLoading = false;
    });
  }

  Future<void> _addUpdate() async {
    if (_selectedUpdateType == null || _selectedCondition == null ||
        _updateNotesController.text.trim().isEmpty) return;
    setState(() => _isLoading = true);

    final entry = {
      'type': _selectedUpdateType,
      'notes': _updateNotesController.text.trim(),
      'condition': _selectedCondition,
      'medicationGiven': _medicationController.text.trim(),
      'timestamp': Timestamp.now(),
      'addedBy': 'Admin Staff',
    };

    await FirebaseFirestore.instance
        .collection('animals')
        .doc(widget.animalId)
        .update({
      'currentCondition': _selectedCondition,
      'treatmentLog': FieldValue.arrayUnion([entry]),
      if (_selectedCondition == 'Deceased') 'adoptionStatus': 'deceased',
    });

    if (mounted) setState(() {
      _showUpdateForm = false;
      _selectedUpdateType = null;
      _selectedCondition = null;
      _updateNotesController.clear();
      _medicationController.clear();
      _isLoading = false;
    });
  }

  Future<void> _markAdopted() async {
    await FirebaseFirestore.instance
        .collection('animals')
        .doc(widget.animalId)
        .update({'adoptionStatus': 'adopted', 'status': 'adopted'});
    if (mounted) Navigator.pop(context);
  }

  Future<void> _markDeceased() async {
    await FirebaseFirestore.instance
        .collection('animals')
        .doc(widget.animalId)
        .update({'adoptionStatus': 'deceased', 'status': 'deceased'});
    if (mounted) Navigator.pop(context);
  }

  Future<void> _removeRecord() async {
    await FirebaseFirestore.instance
        .collection('animals')
        .doc(widget.animalId)
        .delete();
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance
          .collection('animals')
          .doc(widget.animalId)
          .snapshots(),
      builder: (context, snapshot) {
        final data = snapshot.hasData
            ? (snapshot.data!.data() as Map<String, dynamic>? ?? widget.data)
            : widget.data;

        final treatmentLog = List<Map<String, dynamic>>.from(
            data['treatmentLog'] ?? []).reversed.toList();
        final isInTreatment = data['adoptionStatus'] == 'in_treatment';
        final species = (data['species'] ?? '').toString().toLowerCase();
        final isDog = species == 'dog';

        return Scaffold(
          backgroundColor: AppColors.background,
          appBar: AppBar(
            backgroundColor: AppColors.textPrimary,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back, color: AppColors.background),
              onPressed: () => Navigator.pop(context),
            ),
            title: Text('Animal Records',
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
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Photo area
                Container(
                  height: 200,
                  width: double.infinity,
                  color: AppColors.tearspwn,
                  child: const Icon(Icons.pets,
                      size: 64, color: AppColors.textSecondary),
                ),

                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Name + actions
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              Text(data['name'] ?? 'Unnamed',
                                  style: GoogleFonts.tiltWarp(
                                      fontSize: 24,
                                      color: AppColors.textPrimary)),
                              const SizedBox(width: 8),
                              const Icon(Icons.search,
                                  size: 20, color: AppColors.textPrimary),
                            ],
                          ),
                          const Icon(Icons.share_outlined,
                              size: 20, color: AppColors.textPrimary),
                        ],
                      ),

                      const SizedBox(height: 12),

                      // Tab switcher
                      Container(
                        decoration: BoxDecoration(
                          color: AppColors.slaterspwn,
                          borderRadius: BorderRadius.circular(50),
                        ),
                        child: Row(
                          children: [
                            _Tab(label: 'Overview', index: 0,
                                currentIndex: _tabIndex,
                                onTap: (i) => setState(() => _tabIndex = i)),
                            _Tab(label: 'Care', index: 1,
                                currentIndex: _tabIndex,
                                onTap: (i) => setState(() => _tabIndex = i)),
                            _Tab(label: 'Admin', index: 2,
                                currentIndex: _tabIndex,
                                onTap: (i) => setState(() => _tabIndex = i)),
                          ],
                        ),
                      ),

                      const SizedBox(height: 16),

                      // Tab content
                      if (_tabIndex == 0)
                        _OverviewTab(data: data)
                      else if (_tabIndex == 1)
                        _CareTab(
                          data: data,
                          animalId: widget.animalId,
                          isDog: isDog,
                          isInTreatment: isInTreatment,
                          treatmentLog: treatmentLog,
                          showAllLogs: _showAllLogs,
                          onToggleLogs: () => setState(
                                  () => _showAllLogs = !_showAllLogs),
                          showAdmitForm: _showAdmitForm,
                          showUpdateForm: _showUpdateForm,
                          clinicNameController: _clinicNameController,
                          admitDate: _admitDate,
                          onAdmitDatePick: () async {
                            final picked = await showDatePicker(
                              context: context,
                              initialDate: DateTime.now(),
                              firstDate: DateTime(2020),
                              lastDate: DateTime.now(),
                            );
                            if (picked != null)
                              setState(() => _admitDate = picked);
                          },
                          onAdmit: _admit,
                          onToggleAdmit: () => setState(
                                  () => _showAdmitForm = !_showAdmitForm),
                          updateTypes: _updateTypes,
                          conditions: _conditions,
                          selectedUpdateType: _selectedUpdateType,
                          selectedCondition: _selectedCondition,
                          onUpdateTypeChanged: (v) =>
                              setState(() => _selectedUpdateType = v),
                          onConditionChanged: (v) =>
                              setState(() => _selectedCondition = v),
                          updateNotesController: _updateNotesController,
                          medicationController: _medicationController,
                          onAddUpdate: _addUpdate,
                          onToggleUpdate: () => setState(
                                  () => _showUpdateForm = !_showUpdateForm),
                          isLoading: _isLoading,
                        )
                      else
                        _AdminTab(
                          data: data,
                          animalId: widget.animalId,
                          onMarkAdopted: _markAdopted,
                          onMarkDeceased: _markDeceased,
                          onRemove: _removeRecord,
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

// Tab widget
class _Tab extends StatelessWidget {
  final String label;
  final int index;
  final int currentIndex;
  final Function(int) onTap;

  const _Tab({
    required this.label,
    required this.index,
    required this.currentIndex,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final selected = index == currentIndex;
    return Expanded(
      child: GestureDetector(
        onTap: () => onTap(index),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: selected ? AppColors.yellowrspwn : Colors.transparent,
            borderRadius: BorderRadius.circular(50),
          ),
          child: Center(
            child: Text(label,
                style: GoogleFonts.zain(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary)),
          ),
        ),
      ),
    );
  }
}

// Overview tab
class _OverviewTab extends StatelessWidget {
  final Map<String, dynamic> data;
  const _OverviewTab({required this.data});

  @override
  Widget build(BuildContext context) {
    final characteristics =
    List<String>.from(data['keyCharacteristics'] ?? []);
    final rescueBackground =
    List<String>.from(data['rescueBackground'] ?? []);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionLabel('Key Characteristics'),
        const SizedBox(height: 6),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Wrap(
              spacing: 8, runSpacing: 6,
              children: characteristics
                  .map((c) => _YellowTag(label: c))
                  .toList(),
            ),
            const Icon(Icons.edit_outlined,
                size: 18, color: AppColors.textSecondary),
          ],
        ),

        const SizedBox(height: 16),

        _SectionLabel('Rescue Background'),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8, runSpacing: 6,
          children: rescueBackground
              .map((r) => _YellowTag(label: r))
              .toList(),
        ),

        const SizedBox(height: 16),

        _SectionLabel('Description'),
        const SizedBox(height: 6),
        Text(data['description'] ?? '-',
            style: GoogleFonts.zain(
                fontSize: 14,
                color: AppColors.textPrimary,
                height: 1.5)),

        const SizedBox(height: 20),

        // Org info
        Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: AppColors.slaterspwn,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.groups_2_outlined,
                  size: 22, color: AppColors.textPrimary),
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Loved by the Gapz',
                    style: GoogleFonts.tiltWarp(
                        fontSize: 14, color: AppColors.textPrimary)),
                Text('Rescued by this organization since',
                    style: GoogleFonts.zain(
                        fontSize: 12, color: AppColors.textSecondary)),
                Text(data['intakeDate'] != null
                    ? '${(data['intakeDate'] as Timestamp).toDate().year}'
                    : '2024',
                    style: GoogleFonts.zain(
                        fontSize: 12, color: AppColors.textSecondary)),
              ],
            ),
          ],
        ),

        const SizedBox(height: 20),

        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: () {},
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: AppColors.textPrimary),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(30)),
                ),
                child: Text('View Applications',
                    style: GoogleFonts.zain(
                        fontSize: 13, color: AppColors.textPrimary)),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: OutlinedButton(
                onPressed: () {},
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: AppColors.textPrimary),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(30)),
                ),
                child: Text('View Donations',
                    style: GoogleFonts.zain(
                        fontSize: 13, color: AppColors.textPrimary)),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

// Care tab
class _CareTab extends StatelessWidget {
  final Map<String, dynamic> data;
  final String animalId;
  final bool isDog;
  final bool isInTreatment;
  final List<Map<String, dynamic>> treatmentLog;
  final bool showAllLogs;
  final VoidCallback onToggleLogs;
  final bool showAdmitForm;
  final bool showUpdateForm;
  final TextEditingController clinicNameController;
  final DateTime? admitDate;
  final VoidCallback onAdmitDatePick;
  final VoidCallback onAdmit;
  final VoidCallback onToggleAdmit;
  final List<String> updateTypes;
  final List<String> conditions;
  final String? selectedUpdateType;
  final String? selectedCondition;
  final Function(String?) onUpdateTypeChanged;
  final Function(String?) onConditionChanged;
  final TextEditingController updateNotesController;
  final TextEditingController medicationController;
  final VoidCallback onAddUpdate;
  final VoidCallback onToggleUpdate;
  final bool isLoading;

  const _CareTab({
    required this.data,
    required this.animalId,
    required this.isDog,
    required this.isInTreatment,
    required this.treatmentLog,
    required this.showAllLogs,
    required this.onToggleLogs,
    required this.showAdmitForm,
    required this.showUpdateForm,
    required this.clinicNameController,
    required this.admitDate,
    required this.onAdmitDatePick,
    required this.onAdmit,
    required this.onToggleAdmit,
    required this.updateTypes,
    required this.conditions,
    required this.selectedUpdateType,
    required this.selectedCondition,
    required this.onUpdateTypeChanged,
    required this.onConditionChanged,
    required this.updateNotesController,
    required this.medicationController,
    required this.onAddUpdate,
    required this.onToggleUpdate,
    required this.isLoading,
  });

  @override
  Widget build(BuildContext context) {
    final dateAdmitted = data['dateAdmitted'] as Timestamp?;
    final dateStr = dateAdmitted != null
        ? 'March ${dateAdmitted.toDate().day}, ${dateAdmitted.toDate().year}'
        : 'N/A';
    int daysInTreatment = 0;
    if (dateAdmitted != null) {
      daysInTreatment =
          DateTime.now().difference(dateAdmitted.toDate()).inDays + 1;
    }

    // Vaccine lists based on species
    final dogVaccines = ['5-in-1', 'Bordetella'];
    final catVaccines = ['3-in-1', 'FeLV'];
    final extraVaccines = isDog ? dogVaccines : catVaccines;
    final givenVaccines = List<String>.from(data['vaccinesGiven'] ?? []);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Treatment status header
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              isInTreatment ? 'In Treatment' : 'Not In Treatment',
              style: GoogleFonts.tiltWarp(
                  fontSize: 15, color: AppColors.textPrimary),
            ),
            const Icon(Icons.keyboard_arrow_up,
                color: AppColors.textPrimary),
          ],
        ),

        const SizedBox(height: 12),

        // Treatment info grid
        Row(
          children: [
            Expanded(
                child: _InfoItem('Vet Clinic Name',
                    data['vetClinicName'] ?? 'N/A')),
            Expanded(
                child: _InfoItem(
                    'Days in Treatment', '$daysInTreatment')),
          ],
        ),
        Row(
          children: [
            Expanded(child: _InfoItem('Date Admitted', dateStr)),
            Expanded(
                child: _InfoItem('Animal Status',
                    data['currentCondition'] ?? 'Stable')),
          ],
        ),

        const SizedBox(height: 16),

        // Health checkboxes
        _SectionLabel('Health'),
        const SizedBox(height: 8),
        Row(
          children: [
            _CheckDisplay(
                label: 'Vaccinated',
                checked: data['vaccinated'] == true),
            const SizedBox(width: 16),
            _CheckDisplay(
                label: 'Spayed/Neutered',
                checked: data['spayedNeutered'] == true),
            const SizedBox(width: 16),
            _CheckDisplay(
                label: 'Dewormed',
                checked: data['dewormed'] == true),
          ],
        ),

        const SizedBox(height: 16),

        // Vaccines
        _SectionLabel('Vaccines'),
        const SizedBox(height: 8),
        // Rabies always shown
        _CheckDisplay(
            label: 'Rabies', checked: givenVaccines.contains('Rabies')),
        const SizedBox(height: 6),
        // Species-specific vaccines
        Wrap(
          spacing: 16, runSpacing: 6,
          children: extraVaccines
              .map((v) => _CheckDisplay(
              label: v, checked: givenVaccines.contains(v)))
              .toList(),
        ),

        const SizedBox(height: 16),

        // Treatment Logs
        _SectionLabel('Treatment Logs'),
        const SizedBox(height: 8),

        if (treatmentLog.isEmpty)
          Text('No treatment logs yet.',
              style: GoogleFonts.zain(
                  fontSize: 13, color: AppColors.textSecondary))
        else ...[
          ...(showAllLogs
              ? treatmentLog
              : treatmentLog.take(2).toList())
              .map((log) => _TreatmentLogCard(log: log)),
          if (treatmentLog.length > 2)
            Center(
              child: GestureDetector(
                onTap: onToggleLogs,
                child: Icon(
                  showAllLogs
                      ? Icons.keyboard_arrow_up
                      : Icons.keyboard_arrow_down,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
        ],

        const SizedBox(height: 24),

        // Admit form
        if (showAdmitForm) ...[
          _AdmitForm(
            clinicNameController: clinicNameController,
            admitDate: admitDate,
            onDatePick: onAdmitDatePick,
            onConfirm: onAdmit,
            isLoading: isLoading,
          ),
          const SizedBox(height: 16),
        ],

        // Update form
        if (showUpdateForm) ...[
          _UpdateForm(
            updateTypes: updateTypes,
            conditions: conditions,
            selectedUpdateType: selectedUpdateType,
            selectedCondition: selectedCondition,
            onUpdateTypeChanged: onUpdateTypeChanged,
            onConditionChanged: onConditionChanged,
            notesController: updateNotesController,
            medicationController: medicationController,
            onAdd: onAddUpdate,
            isLoading: isLoading,
          ),
          const SizedBox(height: 16),
        ],

        // Admit + Add Update buttons
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: onToggleAdmit,
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: AppColors.textPrimary),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(30)),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                child: Text('Admit',
                    style: GoogleFonts.tiltWarp(
                        fontSize: 15,
                        color: AppColors.textPrimary)),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: ElevatedButton(
                onPressed: onToggleUpdate,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.yellowrspwn,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(30)),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                child: Text(
                  showUpdateForm ? 'Hide Form' : 'Add Update',
                  style: GoogleFonts.tiltWarp(
                      fontSize: 15, color: AppColors.textPrimary),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

// Admin tab
class _AdminTab extends StatelessWidget {
  final Map<String, dynamic> data;
  final String animalId;
  final VoidCallback onMarkAdopted;
  final VoidCallback onMarkDeceased;
  final VoidCallback onRemove;

  const _AdminTab({
    required this.data,
    required this.animalId,
    required this.onMarkAdopted,
    required this.onMarkDeceased,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final intakeDate = data['intakeDate'] as Timestamp?;
    final intakeDateStr = intakeDate != null
        ? '${intakeDate.toDate().month}/${intakeDate.toDate().day}/${intakeDate.toDate().year}'
        : 'mm/dd/yyyy';

    int daysInShelter = 0;
    if (intakeDate != null) {
      daysInShelter =
          DateTime.now().difference(intakeDate.toDate()).inDays;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Info grid
        Row(
          children: [
            Expanded(child: _InfoItem('Intake Date', intakeDateStr)),
            Expanded(
                child: _InfoItem(
                    'Days in Shelter', '$daysInShelter')),
          ],
        ),

        const SizedBox(height: 8),

        // Rescue case link
        GestureDetector(
          onTap: () {},
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Rescue Case',
                  style: GoogleFonts.zain(
                      fontSize: 12, color: AppColors.textSecondary)),
              Text(
                'CASE ID: ${(data['linkedCaseId'] ?? '').toString().substring(0, min(5, (data['linkedCaseId'] ?? '').toString().length)).toUpperCase()}',
                style: GoogleFonts.zain(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary),
              ),
              Text('View Rescue Record',
                  style: GoogleFonts.zain(
                      fontSize: 12,
                      color: AppColors.greenrspwn,
                      decoration: TextDecoration.underline)),
            ],
          ),
        ),

        const SizedBox(height: 8),

        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Total Expenses',
                      style: GoogleFonts.zain(
                          fontSize: 12, color: AppColors.textSecondary)),
                  Text('P xx,xxx',
                      style: GoogleFonts.zain(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary)),
                  Text('View Expense Record',
                      style: GoogleFonts.zain(
                          fontSize: 12,
                          color: AppColors.greenrspwn,
                          decoration: TextDecoration.underline)),
                ],
              ),
            ),
          ],
        ),

        const SizedBox(height: 24),

        // Action buttons
        Row(
          children: [
            Expanded(
              child: ElevatedButton(
                onPressed: onMarkAdopted,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.yellowrspwn,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(30)),
                ),
                child: Text('Mark as Adopted',
                    style: GoogleFonts.zain(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary)),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: ElevatedButton(
                onPressed: () {},
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.yellowrspwn,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(30)),
                ),
                child: Text('Transfer',
                    style: GoogleFonts.zain(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary)),
              ),
            ),
          ],
        ),

        const SizedBox(height: 12),

        Row(
          children: [
            Expanded(
              child: ElevatedButton(
                onPressed: onMarkDeceased,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.yellowrspwn,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(30)),
                ),
                child: Text('Mark as Deceased',
                    style: GoogleFonts.zain(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary)),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: ElevatedButton(
                onPressed: () => _confirmRemove(context),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.yellowrspwn,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(30)),
                ),
                child: Text('Remove',
                    style: GoogleFonts.zain(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Colors.red)),
              ),
            ),
          ],
        ),
      ],
    );
  }

  void _confirmRemove(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.background,
        title: Text('Remove Record',
            style: GoogleFonts.tiltWarp(
                fontSize: 16, color: AppColors.textPrimary)),
        content: Text(
            'Are you sure you want to permanently remove this animal record?',
            style: GoogleFonts.zain(
                fontSize: 14, color: AppColors.textSecondary)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel',
                style: GoogleFonts.zain(color: AppColors.textSecondary)),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              onRemove();
            },
            style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red, elevation: 0),
            child: Text('Remove',
                style: GoogleFonts.zain(color: Colors.white)),
          ),
        ],
      ),
    );
  }
}

// Admit form bottom sheet
class _AdmitForm extends StatelessWidget {
  final TextEditingController clinicNameController;
  final DateTime? admitDate;
  final VoidCallback onDatePick;
  final VoidCallback onConfirm;
  final bool isLoading;

  const _AdmitForm({
    required this.clinicNameController,
    required this.admitDate,
    required this.onDatePick,
    required this.onConfirm,
    required this.isLoading,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.06), blurRadius: 8)
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Text('Admit',
                style: GoogleFonts.tiltWarp(
                    fontSize: 18, color: AppColors.textPrimary)),
          ),
          const SizedBox(height: 16),

          Text('Vet Clinic Name',
              style: GoogleFonts.zain(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary)),
          TextField(
            controller: clinicNameController,
            decoration: InputDecoration(
              hintText: 'Enter',
              hintStyle:
              GoogleFonts.zain(color: AppColors.textSecondary),
              enabledBorder: const UnderlineInputBorder(
                  borderSide:
                  BorderSide(color: AppColors.textPrimary)),
              focusedBorder: const UnderlineInputBorder(
                  borderSide: BorderSide(
                      color: AppColors.textPrimary, width: 1.5)),
              isDense: true,
              contentPadding: const EdgeInsets.only(bottom: 8),
            ),
            style: GoogleFonts.zain(
                fontSize: 14, color: AppColors.textPrimary),
          ),

          const SizedBox(height: 16),

          Text('Date Admitted',
              style: GoogleFonts.zain(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary)),
          GestureDetector(
            onTap: onDatePick,
            child: Container(
              padding: const EdgeInsets.only(bottom: 8),
              decoration: const BoxDecoration(
                border: Border(
                    bottom: BorderSide(color: AppColors.textPrimary)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    admitDate == null
                        ? 'mm/dd/yyyy'
                        : '${admitDate!.month}/${admitDate!.day}/${admitDate!.year}',
                    style: GoogleFonts.zain(
                        fontSize: 14,
                        color: admitDate == null
                            ? AppColors.textSecondary
                            : AppColors.textPrimary),
                  ),
                  const Icon(Icons.calendar_today_outlined,
                      size: 16, color: AppColors.textPrimary),
                ],
              ),
            ),
          ),

          const SizedBox(height: 24),

          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: isLoading ? null : onConfirm,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.yellowrspwn,
                elevation: 0,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(30)),
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              child: isLoading
                  ? const SizedBox(
                  height: 20, width: 20,
                  child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AppColors.textPrimary))
                  : Text('Confirm Admission',
                  style: GoogleFonts.tiltWarp(
                      fontSize: 15,
                      color: AppColors.textPrimary)),
            ),
          ),
        ],
      ),
    );
  }
}

// Update form
class _UpdateForm extends StatelessWidget {
  final List<String> updateTypes;
  final List<String> conditions;
  final String? selectedUpdateType;
  final String? selectedCondition;
  final Function(String?) onUpdateTypeChanged;
  final Function(String?) onConditionChanged;
  final TextEditingController notesController;
  final TextEditingController medicationController;
  final VoidCallback onAdd;
  final bool isLoading;

  const _UpdateForm({
    required this.updateTypes,
    required this.conditions,
    required this.selectedUpdateType,
    required this.selectedCondition,
    required this.onUpdateTypeChanged,
    required this.onConditionChanged,
    required this.notesController,
    required this.medicationController,
    required this.onAdd,
    required this.isLoading,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.05), blurRadius: 6)
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Update Type',
              style: GoogleFonts.zain(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary)),
          DropdownButtonFormField<String>(
            value: selectedUpdateType,
            hint: Text('Select',
                style: GoogleFonts.zain(
                    fontSize: 14, color: AppColors.textSecondary)),
            items: updateTypes
                .map((t) => DropdownMenuItem(
                value: t,
                child: Text(t,
                    style: GoogleFonts.zain(fontSize: 14))))
                .toList(),
            onChanged: onUpdateTypeChanged,
            decoration: const InputDecoration(
              isDense: true,
              contentPadding: EdgeInsets.only(bottom: 8),
              enabledBorder: UnderlineInputBorder(
                  borderSide: BorderSide(color: AppColors.textPrimary)),
              focusedBorder: UnderlineInputBorder(
                  borderSide: BorderSide(
                      color: AppColors.textPrimary, width: 1.5)),
            ),
          ),

          const SizedBox(height: 12),

          Text('Notes',
              style: GoogleFonts.zain(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary)),
          TextField(
            controller: notesController,
            decoration: InputDecoration(
              hintText: 'Enter notes',
              hintStyle: GoogleFonts.zain(
                  color: AppColors.textSecondary, fontSize: 14),
              enabledBorder: const UnderlineInputBorder(
                  borderSide: BorderSide(color: AppColors.textPrimary)),
              focusedBorder: const UnderlineInputBorder(
                  borderSide: BorderSide(
                      color: AppColors.textPrimary, width: 1.5)),
              isDense: true,
              contentPadding: const EdgeInsets.only(bottom: 8),
            ),
            style: GoogleFonts.zain(
                fontSize: 14, color: AppColors.textPrimary),
          ),

          const SizedBox(height: 12),

          Text('Overall Condition',
              style: GoogleFonts.zain(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary)),
          DropdownButtonFormField<String>(
            value: selectedCondition,
            hint: Text('Select',
                style: GoogleFonts.zain(
                    fontSize: 14, color: AppColors.textSecondary)),
            items: conditions
                .map((c) => DropdownMenuItem(
                value: c,
                child: Text(c,
                    style: GoogleFonts.zain(fontSize: 14))))
                .toList(),
            onChanged: onConditionChanged,
            decoration: const InputDecoration(
              isDense: true,
              contentPadding: EdgeInsets.only(bottom: 8),
              enabledBorder: UnderlineInputBorder(
                  borderSide: BorderSide(color: AppColors.textPrimary)),
              focusedBorder: UnderlineInputBorder(
                  borderSide: BorderSide(
                      color: AppColors.textPrimary, width: 1.5)),
            ),
          ),

          const SizedBox(height: 12),

          Text('Medication Given',
              style: GoogleFonts.zain(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary)),
          TextField(
            controller: medicationController,
            decoration: InputDecoration(
              hintText: 'Enter notes',
              hintStyle: GoogleFonts.zain(
                  color: AppColors.textSecondary, fontSize: 14),
              enabledBorder: const UnderlineInputBorder(
                  borderSide: BorderSide(color: AppColors.textPrimary)),
              focusedBorder: const UnderlineInputBorder(
                  borderSide: BorderSide(
                      color: AppColors.textPrimary, width: 1.5)),
              isDense: true,
              contentPadding: const EdgeInsets.only(bottom: 8),
            ),
            style: GoogleFonts.zain(
                fontSize: 14, color: AppColors.textPrimary),
          ),

          const SizedBox(height: 24),

          Center(
            child: ElevatedButton(
              onPressed: isLoading ? null : onAdd,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.yellowrspwn,
                fixedSize: const Size(140, 44),
                elevation: 0,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(30)),
              ),
              child: isLoading
                  ? const SizedBox(
                  height: 18, width: 18,
                  child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AppColors.textPrimary))
                  : Text('Edit',
                  style: GoogleFonts.tiltWarp(
                      fontSize: 15,
                      color: AppColors.textPrimary)),
            ),
          ),
        ],
      ),
    );
  }
}

// Shared subwidgets
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

class _SectionLabel extends StatelessWidget {
  final String label;
  const _SectionLabel(this.label);

  @override
  Widget build(BuildContext context) => Text(label,
      style: GoogleFonts.tiltWarp(
          fontSize: 14,
          fontWeight: FontWeight.bold,
          color: AppColors.textPrimary));
}

class _InfoItem extends StatelessWidget {
  final String label;
  final String value;
  const _InfoItem(this.label, this.value);

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: GoogleFonts.zain(
                fontSize: 11, color: AppColors.textSecondary)),
        Text(value,
            style: GoogleFonts.zain(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary)),
      ],
    ),
  );
}

class _CheckDisplay extends StatelessWidget {
  final String label;
  final bool checked;
  const _CheckDisplay({required this.label, required this.checked});

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      SizedBox(
        width: 18, height: 18,
        child: Checkbox(
          value: checked,
          onChanged: null,
          activeColor: AppColors.textPrimary,
          side: const BorderSide(color: AppColors.textPrimary, width: 1.5),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(2)),
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
      ),
      const SizedBox(width: 4),
      Text(label,
          style: GoogleFonts.zain(
              fontSize: 12, color: AppColors.textPrimary)),
    ],
  );
}

class _YellowTag extends StatelessWidget {
  final String label;
  const _YellowTag({required this.label});

  @override
  Widget build(BuildContext context) => Container(
    padding:
    const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
    decoration: BoxDecoration(
      color: AppColors.yellowrspwn,
      borderRadius: BorderRadius.circular(20),
    ),
    child: Text(label,
        style: GoogleFonts.zain(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: AppColors.textPrimary)),
  );
}

int min(int a, int b) => a < b ? a : b;