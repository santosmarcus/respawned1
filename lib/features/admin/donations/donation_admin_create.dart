import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import 'package:respawnd1/app_theme.dart';

class DonationAdminCreatePage extends StatefulWidget {
  const DonationAdminCreatePage({super.key});

  @override
  State<DonationAdminCreatePage> createState() => _DonationAdminCreatePageState();
}

class _DonationAdminCreatePageState extends State<DonationAdminCreatePage> {
  String title = '';
  bool isDog = true;
  String animalName = 'Select';
  String category = 'donation'; // default lowercase
  String description = '';
  String amount = '';
  DateTime? selectedDate;
  bool _isUploading = false;

  bool acceptInKind = false;
  List<Map<String, String>> inKindItems = [];
  final List<String> inKindCategories = [
    'Food & Water',
    'Medicine & Treatment',
    'Supplies & Equipment',
    'Hygiene & Cleaning',
    'Others'
  ];

  XFile? _campaignImage;
  final ImagePicker _picker = ImagePicker();
  late Stream<QuerySnapshot> _animalsStream;

  @override
  void initState() {
    super.initState();
    _animalsStream = FirebaseFirestore.instance
        .collection('animals')
        .snapshots();
  }

  Future<void> _pickImage() async {
    final XFile? image = await _picker.pickImage(source: ImageSource.gallery);
    if (image != null) {
      setState(() {
        _campaignImage = image;
      });
    }
  }

  Future<void> _createCampaign() async {
    final bool isSponsorship = category.toLowerCase() == 'sponsorship';
    if ((!isSponsorship && title.isEmpty) || (!isSponsorship && amount.isEmpty) || animalName == 'Select' || (!isSponsorship && selectedDate == null)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please fill in all required fields')),
      );
      return;
    }

    setState(() => _isUploading = true);

    try {
      String? imageUrl;
      if (_campaignImage != null) {
        final storageRef = FirebaseStorage.instance
            .ref()
            .child('campaigns/${DateTime.now().millisecondsSinceEpoch}.jpg');
        await storageRef.putFile(File(_campaignImage!.path));
        imageUrl = await storageRef.getDownloadURL();
      }

      final uid = FirebaseAuth.instance.currentUser?.uid;

      final campaignData = {
        'title': isSponsorship ? animalName : title,
        'animalName': animalName,
        'type': category.toLowerCase(),
        'targetAmount': double.tryParse(amount) ?? 0.0,
        'collectedAmount': 0.0,
        'description': description,
        'date': selectedDate != null ? Timestamp.fromDate(selectedDate!) : null,
        'isDog': isDog,
        'imageUrl': imageUrl,
        'createdBy': uid,
        'createdAt': FieldValue.serverTimestamp(),
        'backgroundColor': AppColors.tearspwn.value,
        'acceptInKind': acceptInKind,
        'inKindItems': inKindItems,
        'isActive': true,
      };

      await FirebaseFirestore.instance.collection('campaigns').add(campaignData);

      if (mounted) {
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error creating campaign: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isUploading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            Container(
              color: AppColors.textPrimary,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back, color: AppColors.background),
                    onPressed: () => Navigator.pop(context),
                  ),
                  Text(
                    'New Campaign',
                    style: GoogleFonts.tiltWarp(
                        fontSize: 20, color: AppColors.background, fontWeight: FontWeight.bold),
                  ),
                  const Icon(Icons.lightbulb_outline, color: AppColors.background),
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Text(
                        'Create New Campaign',
                        style: GoogleFonts.tiltWarp(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                            color: AppColors.textPrimary),
                      ),
                    ),
                    const SizedBox(height: 20),
                    const LabelWidget('Images'),
                    const SizedBox(height: 10),
                    GestureDetector(
                      onTap: _pickImage,
                      child: Container(
                        height: 100,
                        width: 100,
                        decoration: BoxDecoration(
                          color: AppColors.surface,
                          border: Border.all(color: AppColors.greenrspwn),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: _campaignImage != null
                            ? ClipRRect(
                                borderRadius: BorderRadius.circular(10),
                                child: Image.file(File(_campaignImage!.path), fit: BoxFit.cover),
                              )
                            : const Icon(Icons.add, color: AppColors.greenrspwn, size: 40),
                      ),
                    ),
                    const SizedBox(height: 20),
                    if (category.toLowerCase() == 'donation') ...[
                      const LabelWidget('Title'),
                      TextField(
                        onChanged: (v) => setState(() => title = v),
                        decoration: const InputDecoration(
                          hintStyle: TextStyle(color: AppColors.textSecondary),
                        ),
                      ),
                      const SizedBox(height: 20),
                    ],
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const LabelWidget('Name of Animal'),
                              StreamBuilder<QuerySnapshot>(
                                stream: _animalsStream,
                                builder: (context, snapshot) {
                                  List<DropdownMenuItem<String>> items = [
                                    DropdownMenuItem(
                                      value: 'Select',
                                      child: Text('Select', style: GoogleFonts.zain(color: AppColors.textPrimary)),
                                    )
                                  ];
                                  
                                  if (snapshot.hasData) {
                                    for (var doc in snapshot.data!.docs) {
                                      final name = doc.get('name') as String?;
                                      if (name != null && name.isNotEmpty) {
                                        items.add(DropdownMenuItem(
                                          value: name,
                                          child: Text(name, style: GoogleFonts.zain(color: AppColors.textPrimary)),
                                        ));
                                      }
                                    }
                                  }

                                  // Ensure the current animalName is in the list to prevent assertion errors during loading
                                  if (animalName != 'Select' && !items.any((item) => item.value == animalName)) {
                                    items.add(DropdownMenuItem(
                                      value: animalName,
                                      child: Text(animalName, style: GoogleFonts.zain(color: AppColors.textPrimary)),
                                    ));
                                  }
                                  
                                  return DropdownButtonFormField<String>(
                                    value: animalName,
                                    decoration: const InputDecoration(
                                      border: UnderlineInputBorder(),
                                    ),
                                    items: items,
                                    onChanged: (v) {
                                      if (v != null && v != 'Select') {
                                        final animalDoc = snapshot.data!.docs.firstWhere((doc) => doc.get('name') == v);
                                        final species = animalDoc.get('species') as String?;
                                        setState(() {
                                          animalName = v;
                                          isDog = species == 'Dog';
                                        });
                                      } else {
                                        setState(() {
                                          animalName = 'Select';
                                        });
                                      }
                                    },
                                  );
                                }
                              )
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    const LabelWidget('Donation Category'),
                    DropdownButtonFormField<String>(
                      value: category,
                      decoration: const InputDecoration(
                        border: UnderlineInputBorder(),
                      ),
                      items: ['donation', 'sponsorship']
                          .map<DropdownMenuItem<String>>((e) => DropdownMenuItem(
                              value: e,
                              child: Text(e, style: GoogleFonts.zain(color: AppColors.textPrimary))))
                          .toList(),
                      onChanged: (v) => setState(() => category = v!),
                    ),
                    const SizedBox(height: 20),
                    const LabelWidget('Description'),
                    TextField(
                      onChanged: (v) => setState(() => description = v),
                      decoration: const InputDecoration(
                        hintStyle: TextStyle(color: AppColors.textSecondary),
                      ),
                    ),
                    const SizedBox(height: 20),
                    if (category.toLowerCase() == 'donation') ...[
                      const LabelWidget('Target Amount'),
                      TextField(
                          keyboardType: TextInputType.number,
                          style: const TextStyle(color: AppColors.textPrimary),
                          decoration: const InputDecoration(
                              prefixText: '₱ ', 
                              prefixStyle: TextStyle(color: AppColors.textPrimary),
                              border: OutlineInputBorder()),
                          onChanged: (v) => setState(() => amount = v)),
                      const SizedBox(height: 20),
                    ],
                    if (category.toLowerCase() == 'donation') ...[
                      const LabelWidget('Expected End Date'),
                      TextField(
                          readOnly: true,
                          decoration: InputDecoration(
                              hintText: selectedDate == null ? 'mm/dd/yyyy' : "${selectedDate!.month}/${selectedDate!.day}/${selectedDate!.year}",
                              hintStyle: TextStyle(color: selectedDate == null ? AppColors.textSecondary : AppColors.textPrimary),
                              suffixIcon: const Icon(Icons.calendar_today, color: AppColors.textPrimary)),
                          onTap: () async {
                            final picked = await showDatePicker(
                              context: context,
                              initialDate: DateTime.now(),
                              firstDate: DateTime.now(),
                              lastDate: DateTime(2100),
                            );
                            if (picked != null) {
                              setState(() => selectedDate = picked);
                            }
                          }),
                      const SizedBox(height: 20),
                    ],
                    if (category.toLowerCase() == 'donation') ...[
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const LabelWidget('Accept In-Kind donations'),
                          GestureDetector(
                            onTap: () => setState(() => acceptInKind = !acceptInKind),
                            child: Container(
                              width: 24,
                              height: 24,
                              decoration: BoxDecoration(
                                color: acceptInKind ? const Color(0xFF4A4E1A) : Colors.transparent,
                                border: Border.all(color: const Color(0xFF4A4E1A), width: 2),
                              ),
                            ),
                          ),
                        ],
                      ),
                      if (acceptInKind) ...[
                        const SizedBox(height: 15),
                        ...inKindItems.asMap().entries.map((entry) {
                          int idx = entry.key;
                          Map<String, String> item = entry.value;
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: Row(
                              children: [
                                Container(
                                  width: 100,
                                  decoration: BoxDecoration(
                                    color: AppColors.surface,
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(color: AppColors.textPrimary.withOpacity(0.2)),
                                  ),
                                  padding: const EdgeInsets.symmetric(horizontal: 8),
                                  child: DropdownButton<String>(
                                    value: item['category'],
                                    isExpanded: true,
                                    underline: const SizedBox(),
                                    hint: Text('Select', style: GoogleFonts.zain(fontSize: 14)),
                                    items: inKindCategories.map((cat) => DropdownMenuItem(
                                      value: cat,
                                      child: Text(cat, style: GoogleFonts.zain(fontSize: 14, color: AppColors.textPrimary)),
                                    )).toList(),
                                    onChanged: (v) {
                                      setState(() {
                                        inKindItems[idx]['category'] = v!;
                                      });
                                    },
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: TextField(
                                    onChanged: (v) => inKindItems[idx]['description'] = v,
                                    controller: TextEditingController(text: item['description'])..selection = TextSelection.collapsed(offset: item['description']?.length ?? 0),
                                    decoration: InputDecoration(
                                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                      fillColor: AppColors.surface,
                                      filled: true,
                                      enabledBorder: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(8),
                                        borderSide: BorderSide(color: AppColors.textPrimary.withOpacity(0.2)),
                                      ),
                                      focusedBorder: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(8),
                                        borderSide: const BorderSide(color: AppColors.greenrspwn),
                                      ),
                                    ),
                                  ),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.delete_outline, color: AppColors.textPrimary),
                                  onPressed: () => setState(() => inKindItems.removeAt(idx)),
                                ),
                              ],
                            ),
                          );
                        }),
                        Center(
                          child: IconButton(
                            icon: const Icon(Icons.add_circle_outline, color: AppColors.textPrimary),
                            onPressed: () => setState(() => inKindItems.add({'category': 'Others', 'description': ''})),
                          ),
                        ),
                      ],
                    ],
                    const SizedBox(height: 40),
                    Center(
                      child: _isUploading 
                        ? const CircularProgressIndicator(color: AppColors.yellowrspwn)
                        : ElevatedButton(
                            style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.yellowrspwn,
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 50, vertical: 15)),
                            onPressed: _createCampaign,
                            child: Text('Create Campaign',
                                style: GoogleFonts.tiltWarp(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                    color: AppColors.textPrimary)),
                          ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class LabelWidget extends StatelessWidget {
  final String text;
  const LabelWidget(this.text, {super.key});
  @override
  Widget build(BuildContext context) =>
      Text(text, style: GoogleFonts.tiltWarp(fontWeight: FontWeight.bold, fontSize: 16, color: AppColors.textPrimary));
}
