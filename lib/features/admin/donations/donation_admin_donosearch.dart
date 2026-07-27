import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:respawnd1/app_theme.dart';
import 'donation_admin_provider.dart';
import 'donation_admin_models.dart';
import 'donation_admin_donoinfo.dart';

class DonationSearchPage extends StatelessWidget {
  const DonationSearchPage({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<DonationAdminProvider>(context);
    final DateFormat formatter = DateFormat('yyyy-MM-dd HH:mm');

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Column(
        children: [
          Container(
            color: AppColors.textPrimary,
            padding: const EdgeInsets.only(top: 50, left: 16, right: 16, bottom: 20),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                IconButton(
                  icon: const Icon(Icons.arrow_back_ios, color: AppColors.background),
                  onPressed: () => Navigator.pop(context),
                ),
                Text(
                  "Search Donations",
                  style: GoogleFonts.tiltWarp(color: AppColors.background, fontSize: 22),
                ),
                const Icon(Icons.lightbulb_outline, color: AppColors.background),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(20.0),
            child: Column(
              children: [
                TextField(
                  onChanged: provider.updateDonationSearch,
                  decoration: InputDecoration(
                    filled: true,
                    fillColor: AppColors.tearspwn,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                    prefixIcon: const Icon(Icons.search, color: AppColors.textPrimary),
                    hintText: "Search by donor name...",
                    hintStyle: GoogleFonts.zain(color: AppColors.textSecondary),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  onChanged: provider.updateDonationCampaignSearch,
                  decoration: InputDecoration(
                    filled: true,
                    fillColor: AppColors.tearspwn,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                    prefixIcon: const Icon(Icons.campaign, color: AppColors.textPrimary),
                    hintText: "Search by campaign...",
                    hintStyle: GoogleFonts.zain(color: AppColors.textSecondary),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () async {
                          final picked = await showDatePicker(
                            context: context,
                            initialDate: provider.startDate ?? DateTime.now(),
                            firstDate: DateTime(2020),
                            lastDate: DateTime.now().add(const Duration(days: 365)),
                          );
                          if (picked != null) {
                            provider.updateDonationDates(picked, provider.endDate);
                          }
                        },
                        icon: const Icon(Icons.calendar_today, size: 16),
                        label: Text(
                          provider.startDate == null 
                            ? "Start Date" 
                            : DateFormat('MM/dd/yy').format(provider.startDate!),
                          style: GoogleFonts.zain(fontWeight: FontWeight.bold),
                        ),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.textPrimary,
                          side: const BorderSide(color: AppColors.textPrimary),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () async {
                          final picked = await showDatePicker(
                            context: context,
                            initialDate: provider.endDate ?? DateTime.now(),
                            firstDate: provider.startDate ?? DateTime(2020),
                            lastDate: DateTime.now().add(const Duration(days: 365)),
                          );
                          if (picked != null) {
                            provider.updateDonationDates(provider.startDate, picked);
                          }
                        },
                        icon: const Icon(Icons.calendar_today, size: 16),
                        label: Text(
                          provider.endDate == null 
                            ? "End Date" 
                            : DateFormat('MM/dd/yy').format(provider.endDate!),
                          style: GoogleFonts.zain(fontWeight: FontWeight.bold),
                        ),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.textPrimary,
                          side: const BorderSide(color: AppColors.textPrimary),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                    ),
                    if (provider.startDate != null || provider.endDate != null)
                      IconButton(
                        onPressed: () => provider.updateDonationDates(null, null),
                        icon: const Icon(Icons.clear, color: Colors.redAccent),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                if (provider.donationTabIndex == 2 || provider.donationTabIndex == 3)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                      color: AppColors.tearspwn,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: provider.statusFilter,
                        icon: const Icon(Icons.filter_list, color: AppColors.textPrimary),
                        isExpanded: true,
                        style: GoogleFonts.zain(color: AppColors.textPrimary, fontWeight: FontWeight.bold, fontSize: 16),
                        dropdownColor: AppColors.tearspwn,
                        borderRadius: BorderRadius.circular(12),
                        onChanged: (String? newValue) {
                          if (newValue != null) {
                            provider.updateStatusFilter(newValue);
                          }
                        },
                        items: (provider.donationTabIndex == 3 
                          ? ['All', 'In-Progress', 'Complete'] 
                          : ['All', 'Active', 'Inactive'])
                            .map<DropdownMenuItem<String>>((String value) {
                          return DropdownMenuItem<String>(
                            value: value,
                            child: Text(value == 'All' ? 'All Status' : value),
                          );
                        }).toList(),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: ['All', 'Monetary', 'Sponsorships', 'In-Kind'].asMap().entries.map<Widget>((e) {
                final isSelected = provider.donationTabIndex == e.key;
                return GestureDetector(
                  onTap: () => provider.updateDonationTab(e.key),
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
          ),
          const Divider(height: 32),
          Expanded(
            child: provider.filteredDonations.isEmpty
              ? Center(child: Text("No donations found.", style: GoogleFonts.zain(color: AppColors.textSecondary, fontSize: 18)))
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  itemCount: provider.filteredDonations.length,
                  itemBuilder: (ctx, i) {
                    final item = provider.filteredDonations[i];
                    final date = item.timestamp?.toDate() ?? DateTime.now();
                    return GestureDetector(
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => DonationDetailsScreen(donation: item)),
                        );
                      },
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 16),
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: AppColors.surface,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: Colors.black.withValues(alpha: 0.05)),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.03),
                              blurRadius: 4,
                              offset: const Offset(0, 2),
                            )
                          ],
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    "${formatter.format(date)} | ${provider.getCampaignTitle(item.campaignId)}", 
                                    style: GoogleFonts.zain(fontSize: 12, color: AppColors.textSecondary),
                                  ),
                                  Text(
                                    item.amount, 
                                    style: GoogleFonts.tiltWarp(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                                  ),
                                  Text(
                                    "${item.title}${item.type != 'donation' ? ' (${item.type})' : ''}",
                                    style: GoogleFonts.zain(fontSize: 14),
                                  ),
                                  if (item.type == 'inkind' && item.status.isNotEmpty)
                                    Container(
                                      margin: const EdgeInsets.only(top: 4),
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: item.status == 'complete' ? AppColors.greenrspwn.withValues(alpha: 0.1) : AppColors.yellowrspwn.withValues(alpha: 0.1),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Text(
                                        item.status.toUpperCase(),
                                        style: GoogleFonts.tiltWarp(
                                          fontSize: 10,
                                          color: item.status == 'complete' ? AppColors.greenrspwn : AppColors.textPrimary,
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                            const Icon(Icons.chevron_right, color: AppColors.textPrimary),
                          ],
                        ),
                      ),
                    );
                  },
                ),
          )
        ],
      ),
    );
  }
}
