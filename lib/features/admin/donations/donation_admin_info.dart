import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import 'package:provider/provider.dart';
import 'package:respawnd1/app_theme.dart';
import 'donation_admin_models.dart';
import 'donation_admin_provider.dart';
import 'package:intl/intl.dart';
import 'donation_admin_donoinfo.dart';
import 'donation_admin_donosearch.dart';

class DonationAdminInfoPage extends StatefulWidget {
  final DonationCampaign? campaign;
  const DonationAdminInfoPage({super.key, this.campaign});

  @override
  State<DonationAdminInfoPage> createState() => _DonationAdminInfoPageState();
}

class _DonationAdminInfoPageState extends State<DonationAdminInfoPage> {
  bool _isEndingCampaign = false;
  int _selectedDonationType = 0; // 0: All, 1: Monetary, 2: In-Kind

  @override
  void initState() {
    super.initState();
    if (widget.campaign != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        context.read<DonationAdminProvider>().fetchFundAllocations(widget.campaign!.id);
      });
    }
  }

  void _openAllocationDialog(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.background,
      builder: (context) => AllocateFundsSheet(campaignId: widget.campaign?.id),
    );
  }

  Future<void> _endCampaign() async {
    final campaign = widget.campaign;
    if (campaign == null) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('End Campaign', style: GoogleFonts.tiltWarp(color: AppColors.textPrimary)),
        content: Text('Are you sure you want to end this campaign? This cannot be undone.', style: GoogleFonts.zain(color: AppColors.textPrimary, fontSize: 18)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Cancel', style: GoogleFonts.zain(color: AppColors.textSecondary, fontSize: 18)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text('End', style: GoogleFonts.zain(color: Colors.red, fontSize: 18, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() => _isEndingCampaign = true);

    try {
      await context.read<DonationAdminProvider>().endCampaign(
        campaign.id,
        campaign.type,
        campaign.title,
        campaign.animalName,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Campaign ended successfully')),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error ending campaign: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isEndingCampaign = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool isActive = widget.campaign?.isActive ?? true;

    return Scaffold(
      body: Column(
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(16, 48, 16, 24),
            color: AppColors.textPrimary,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                IconButton(
                  icon: const Icon(Icons.arrow_back, color: AppColors.background),
                  onPressed: () => Navigator.pop(context),
                ),
                Text(
                  widget.campaign?.type == 'sponsorship' ? "Sponsorship" : "Donation",
                  style: GoogleFonts.tiltWarp(fontSize: 20, color: AppColors.background, fontWeight: FontWeight.bold),
                ),
                const Icon(Icons.lightbulb_outline, color: AppColors.background),
              ],
            ),
          ),
          Expanded(
            child: Consumer<DonationAdminProvider>(
              builder: (context, data, child) => SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(child: Text(widget.campaign?.title ?? "Help Mickey battle Parvovirus!", style: GoogleFonts.tiltWarp(fontSize: 22, fontWeight: FontWeight.bold, color: AppColors.textPrimary))),
                        if (!isActive)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.red.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(color: Colors.red),
                            ),
                            child: Text("ENDED", style: GoogleFonts.zain(color: Colors.red, fontWeight: FontWeight.bold)),
                          ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        _StatColumn("Total Received", "₱${widget.campaign?.collectedAmount.toStringAsFixed(0) ?? '0'}"),
                        if (widget.campaign?.type != 'sponsorship')
                          _StatColumn("Target Funds", "₱${widget.campaign?.targetAmount.toStringAsFixed(0) ?? '0'}"),
                        _StatColumn("Available Balance", "₱${(widget.campaign?.collectedAmount ?? 0).toStringAsFixed(0)}"),
                      ],
                    ),
                    const Divider(height: 40),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text("Fund Tracking", style: GoogleFonts.tiltWarp(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
                        IconButton(
                          icon: const Icon(Icons.add_circle_outline, color: AppColors.textPrimary),
                          onPressed: isActive ? () => _openAllocationDialog(context) : null,
                        ),
                      ],
                    ),
                    const SizedBox(height: 15),
                    if (data.fundAllocations.isEmpty)
                      Center(child: Text("No fund allocations yet.", style: GoogleFonts.zain(color: AppColors.textSecondary)))
                    else
                      ...data.fundAllocations.map<Widget>((f) => _FundItem(f)),
                    const Divider(height: 40),
                    Text(
                      widget.campaign?.type == 'sponsorship' ? "Active Sponsors" : "Recent Activity",
                      style: GoogleFonts.tiltWarp(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                    ),
                    const SizedBox(height: 15),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: ['All', 'Monetary', 'In-Kind'].asMap().entries.map<Widget>((e) {
                        final isSelected = _selectedDonationType == e.key;
                        return GestureDetector(
                          onTap: () => setState(() => _selectedDonationType = e.key),
                          child: Column(
                            children: [
                              Text(
                                e.value,
                                style: GoogleFonts.tiltWarp(
                                  fontSize: 16,
                                  color: isSelected ? AppColors.textPrimary : AppColors.textSecondary,
                                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                ),
                              ),
                              const SizedBox(height: 4),
                              if (isSelected) 
                                Container(height: 3, width: 30, color: AppColors.textPrimary),
                            ],
                          ),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 10),
                    // This section could also be a StreamBuilder from the global donations collection filtered by campaignId
                    StreamBuilder<QuerySnapshot>(
                      stream: FirebaseFirestore.instance
                          .collection('donations')
                          .where('campaignId', isEqualTo: widget.campaign?.id)
                          .snapshots(),
                      builder: (context, snapshot) {
                        if (snapshot.hasError) {
                          return Padding(
                            padding: const EdgeInsets.only(top: 10),
                            child: Text("Error: ${snapshot.error}", style: GoogleFonts.zain(color: Colors.red)),
                          );
                        }
                        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                          return Padding(
                            padding: const EdgeInsets.only(top: 10),
                            child: Text("No activity yet for this campaign.", style: GoogleFonts.zain(color: AppColors.textSecondary)),
                          );
                        }

                        // Client-side filtering
                        final allDocs = snapshot.data!.docs.toList();
                        final filteredDocs = allDocs.where((doc) {
                          final data = doc.data() as Map<String, dynamic>;
                          final type = data['type'] as String?;
                          final status = data['status'] as String?;

                          // Filter out cancelled donations (especially in-kind)
                          if (status == 'cancelled') return false;

                          if (_selectedDonationType == 0) return true;
                          if (_selectedDonationType == 1) return type == 'donation' || type == 'sponsorship';
                          if (_selectedDonationType == 2) return type == 'inkind';
                          return true;
                        }).toList();

                        if (filteredDocs.isEmpty) {
                          return Padding(
                            padding: const EdgeInsets.only(top: 10),
                            child: Text("No results for this category.", style: GoogleFonts.zain(color: AppColors.textSecondary)),
                          );
                        }

                        // Client-side sorting and limiting
                        filteredDocs.sort((a, b) {
                          final aData = a.data() as Map<String, dynamic>;
                          final bData = b.data() as Map<String, dynamic>;
                          final aTime = aData['createdAt'] as Timestamp?;
                          final bTime = bData['createdAt'] as Timestamp?;
                          if (aTime == null) return 1;
                          if (bTime == null) return -1;
                          return bTime.compareTo(aTime);
                        });
                        final recentDocs = filteredDocs.take(10).toList();

                        return Column(
                          children: [
                            ...recentDocs.map((doc) {
                              final donation = DonationHistoryRecord.fromFirestore(doc);
                              return InkWell(
                                onTap: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (context) => DonationDetailsScreen(donation: donation),
                                    ),
                                  );
                                },
                                child: _DonationItem(
                                    donation.isAnonymous ? "Anonymous" : donation.donorName, 
                                    donation.date, 
                                    donation.amount,
                                    type: donation.type,
                                    status: donation.status,
                                ),
                              );
                            }),
                            const SizedBox(height: 10),
                            Center(
                              child: TextButton.icon(
                                onPressed: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(builder: (context) => const DonationSearchPage()),
                                  );
                                },
                                icon: const Icon(Icons.search, color: AppColors.textPrimary),
                                label: Text("Search All Donations", style: GoogleFonts.zain(color: AppColors.textPrimary, fontSize: 18, fontWeight: FontWeight.bold)),
                              ),
                            ),
                          ],
                        );
                      }
                    ),
                    const Divider(height: 40),
                    Text("Campaign Analytics", style: GoogleFonts.tiltWarp(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
                    const SizedBox(height: 15),
                    if (widget.campaign?.type == 'sponsorship') ...[
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          StreamBuilder<QuerySnapshot>(
                            stream: FirebaseFirestore.instance
                                .collection('donations')
                                .where('campaignId', isEqualTo: widget.campaign?.id)
                                .where('type', isEqualTo: 'sponsorship')
                                .snapshots(),
                            builder: (context, snapshot) {
                              if (snapshot.hasError) return const _StatColumn("Active Sponsors", "Error");
                              if (!snapshot.hasData) return const _StatColumn("Active Sponsors", "0");
                              
                              final now = DateTime.now();
                              final thirtyDaysAgo = now.subtract(const Duration(days: 30));
                              
                              // Map of userId to their latest donation timestamp
                              final Map<String, DateTime> latestDonations = {};
                              
                              for (var doc in snapshot.data!.docs) {
                                final data = doc.data() as Map<String, dynamic>;
                                final userId = data['userId'] as String?;
                                final timestamp = data['timestamp'] as Timestamp?;
                                
                                if (userId != null && timestamp != null) {
                                  final date = timestamp.toDate();
                                  if (latestDonations[userId] == null || date.isAfter(latestDonations[userId]!)) {
                                    latestDonations[userId] = date;
                                  }
                                }
                              }
                              
                              final activeSponsors = latestDonations.values
                                  .where((date) => date.isAfter(thirtyDaysAgo))
                                  .length;
                                  
                              return _StatColumn("Active Sponsors", activeSponsors.toString());
                            }
                          ),
                          _StatColumn("Status", isActive ? "Ongoing" : "Ended"),
                        ],
                      ),
                    ] else ...[
                      StreamBuilder<QuerySnapshot>(
                        stream: FirebaseFirestore.instance
                            .collection('donations')
                            .where('campaignId', isEqualTo: widget.campaign?.id)
                            .snapshots(),
                        builder: (context, snapshot) {
                          if (snapshot.hasError) {
                            return Center(child: Text("Error: ${snapshot.error}", style: GoogleFonts.zain(color: Colors.red)));
                          }
                          int totalDonations = 0;
                          int uniqueDonors = 0;
                          if (snapshot.hasData) {
                            final docs = snapshot.data!.docs;
                            final eligibleDocs = docs.where((doc) {
                              final data = doc.data() as Map<String, dynamic>;
                              final type = data['type'] as String?;
                              final status = data['status'] as String?;
                              if (type == 'inkind') {
                                return status == 'complete';
                              }
                              return true; // Monetary donations always count
                            }).toList();

                            totalDonations = eligibleDocs.length;
                            uniqueDonors = eligibleDocs.map((doc) {
                              final data = doc.data() as Map<String, dynamic>;
                              return data['userId'] ?? doc.id;
                            }).toSet().length;
                          }

                          return Column(
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                                children: [
                                  _StatColumn("Total Donations", totalDonations.toString()),
                                  _StatColumn("Unique Donors", uniqueDonors.toString()),
                                ],
                              ),
                              const SizedBox(height: 20),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                                children: [
                                  _StatColumn("End Date", widget.campaign?.formattedEndDate ?? "N/A"),
                                  _StatColumn("Days Left", widget.campaign?.daysRemaining ?? "N/A"),
                                ],
                              ),
                            ],
                          );
                        }
                      ),
                    ],
                    const SizedBox(height: 40),
                    if (isActive)
                      Center(
                        child: _isEndingCampaign
                          ? const CircularProgressIndicator(color: Colors.red)
                          : ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.red,
                                padding: const EdgeInsets.symmetric(horizontal: 50, vertical: 15),
                              ),
                              onPressed: _endCampaign,
                              child: Text('End Campaign',
                                style: GoogleFonts.tiltWarp(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
                            ),
                      ),
                    const SizedBox(height: 20),
                  ],
                ),
              ),
            ),
          )
        ],
      ),
    );
  }
}

class AllocateFundsSheet extends StatefulWidget {
  final String? campaignId;
  const AllocateFundsSheet({super.key, this.campaignId});
  @override
  State<AllocateFundsSheet> createState() => _AllocateFundsSheetState();
}

class _AllocateFundsSheetState extends State<AllocateFundsSheet> {
  final List<String> categories = ["Food", "Medicine and Treatment", "Administrative", "Bills and Utilities"];
  String selectedCategory = "Medicine and Treatment";
  bool showDropdown = false;
  bool includeInKind = false;
  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _amountController = TextEditingController();
  final TextEditingController _inKindTextController = TextEditingController();
  bool _isUploading = false;

  XFile? _receiptImage;
  final ImagePicker _picker = ImagePicker();

  Future<void> _pickImage() async {
    final XFile? image = await _picker.pickImage(source: ImageSource.gallery);
    if (image != null) {
      setState(() {
        _receiptImage = image;
      });
    }
  }

  Future<void> _submitData() async {
    if (_titleController.text.isEmpty || _amountController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please fill in title and amount')),
      );
      return;
    }
    
    setState(() => _isUploading = true);

    try {
      String? imageUrl;
      if (_receiptImage != null) {
        final storageRef = FirebaseStorage.instance
            .ref()
            .child('receipts/${DateTime.now().millisecondsSinceEpoch}.jpg');
        await storageRef.putFile(File(_receiptImage!.path));
        imageUrl = await storageRef.getDownloadURL();
      }

      final allocation = FundAllocation(
        id: '', // Generated by Firestore
        title: _titleController.text,
        category: selectedCategory,
        amount: "₱${_amountController.text}",
        date: DateFormat('MMMM d, yyyy').format(DateTime.now()),
        imageUrl: imageUrl,
        campaignId: widget.campaignId,
      );

      await context.read<DonationAdminProvider>().addFundAllocation(allocation);

      if (mounted) {
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error allocating funds: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isUploading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Stack(
              alignment: Alignment.center,
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text("Cancel", style: GoogleFonts.zain(color: Colors.red, fontSize: 18, fontWeight: FontWeight.bold)),
                  ),
                ),
                Text("Allocate Funds", style: GoogleFonts.tiltWarp(fontSize: 20, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
                Align(
                  alignment: Alignment.centerRight,
                  child: _isUploading 
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                    : TextButton(
                        onPressed: _submitData,
                        child: Text("Done", style: GoogleFonts.zain(color: AppColors.textPrimary, fontSize: 18, fontWeight: FontWeight.bold)),
                      ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            TextField(
              controller: _titleController,
              style: GoogleFonts.zain(color: AppColors.textPrimary, fontSize: 18),
              decoration: const InputDecoration(
                hintText: "Enter Title",
                hintStyle: TextStyle(color: AppColors.textSecondary),
                border: UnderlineInputBorder(),
              ),
            ),
            const SizedBox(height: 10),
            GestureDetector(
              onTap: () => setState(() => showDropdown = !showDropdown),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text("Select Category", style: GoogleFonts.zain(color: AppColors.textSecondary, fontSize: 18)),
                    Text(selectedCategory, style: GoogleFonts.zain(fontWeight: FontWeight.bold, color: AppColors.textPrimary, fontSize: 18)),
                  ],
                ),
              ),
            ),
            if (showDropdown)
              ...categories.map((cat) => ListTile(
                title: Text(cat, style: GoogleFonts.zain(color: AppColors.textPrimary, fontSize: 16)),
                onTap: () => setState(() {
                  selectedCategory = cat;
                  showDropdown = false;
                }),
              )),
            const Divider(),
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text("Upload Receipt", style: GoogleFonts.zain(color: AppColors.textSecondary, fontSize: 18)),
                GestureDetector(
                  onTap: _pickImage,
                  child: Container(
                    width: 100,
                    height: 100,
                    decoration: BoxDecoration(
                      color: Colors.transparent,
                      border: Border.all(color: AppColors.greenrspwn, style: BorderStyle.solid),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: _receiptImage != null
                        ? ClipRRect(
                            borderRadius: BorderRadius.circular(10),
                            child: Image.file(File(_receiptImage!.path), fit: BoxFit.cover),
                          )
                        : const Icon(Icons.add, color: AppColors.greenrspwn, size: 40),
                  ),
                ),
              ],
            ),
            const Divider(),
            const SizedBox(height: 10),
            TextField(
              controller: _amountController,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              style: GoogleFonts.zain(color: AppColors.textPrimary, fontSize: 18),
              decoration: const InputDecoration(
                hintText: "Amount",
                prefixText: "₱ ",
                hintStyle: TextStyle(color: AppColors.textSecondary),
                border: UnderlineInputBorder(),
              ),
            ),
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text("Include In-Kind Donations", style: GoogleFonts.zain(color: AppColors.textSecondary, fontSize: 18)),
                Checkbox(
                  value: includeInKind,
                  onChanged: (v) => setState(() => includeInKind = v!),
                  activeColor: AppColors.textPrimary,
                ),
              ],
            ),
            const Divider(),
            TextField(
              controller: _inKindTextController,
              style: GoogleFonts.zain(color: AppColors.textPrimary, fontSize: 18),
              decoration: const InputDecoration(
                hintText: "Type accepted In-Kind Donations",
                hintStyle: TextStyle(color: AppColors.textSecondary),
                border: UnderlineInputBorder(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatColumn extends StatelessWidget {
  final String label, value;
  const _StatColumn(this.label, this.value);
  @override
  Widget build(BuildContext context) => Column(
        children: [
          Text(label, style: GoogleFonts.zain(fontSize: 12, color: AppColors.textSecondary)),
          Text(value, style: GoogleFonts.tiltWarp(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
        ],
      );
}

class _FundItem extends StatelessWidget {
  final FundAllocation item;
  const _FundItem(this.item);
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(item.title, style: GoogleFonts.zain(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
              Text(item.category, style: GoogleFonts.zain(color: AppColors.textSecondary)),
            ]),
            Text(item.amount, style: GoogleFonts.zain(fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
          ],
        ),
      );
}

class _DonationItem extends StatelessWidget {
  final String name, date, amount;
  final String type;
  final String status;
  const _DonationItem(this.name, this.date, this.amount, {this.type = 'donation', this.status = ''});
  @override
  Widget build(BuildContext context) {
    final bool isInKind = type == 'inkind';
    final bool isCompleted = status == 'complete';

    return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            if (isInKind)
              const Padding(
                padding: EdgeInsets.only(right: 12),
                child: Icon(Icons.inventory_2_outlined, color: AppColors.textPrimary, size: 24),
              ),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        name, 
                        style: GoogleFonts.zain(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (isInKind) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: isCompleted ? AppColors.greenrspwn.withOpacity(0.1) : AppColors.yellowrspwn.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: isCompleted ? AppColors.greenrspwn : AppColors.yellowrspwn, width: 0.5),
                        ),
                        child: Text(
                          isCompleted ? "COMPLETED" : "PENDING",
                          style: GoogleFonts.zain(
                            fontSize: 10, 
                            fontWeight: FontWeight.bold, 
                            color: isCompleted ? AppColors.greenrspwn : AppColors.textPrimary
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                Text(date, style: GoogleFonts.zain(color: AppColors.textSecondary)),
              ]),
            ),
            const SizedBox(width: 8),
            Text(amount, style: GoogleFonts.zain(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
          ],
        ),
      );
  }
}
