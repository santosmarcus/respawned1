import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../app_theme.dart';
// NFC disabled for now — only QR is used for collar tags.
// import 'admin_nfc.dart';
import 'admin_qr.dart';
import 'package:respawnd1/features/admin/widgets/admin_drawer.dart';


class AdminCollarTagScreen extends StatelessWidget {
  const AdminCollarTagScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      drawer: const AdminDrawer(),
      appBar: AppBar(
        //leading: IconButton(
        //icon: const Icon(Icons.menu, color: AppColors.background),
        //onPressed: () {},
        //),
        leading: Builder(
          builder: (context) => IconButton(
            icon: const Icon(Icons.menu, color: AppColors.background),
            onPressed: () => Scaffold.of(context).openDrawer(),
          ),
        ),
        backgroundColor: AppColors.textPrimary,
        title: Text(
          'Pet Collar ID Tags',
          style: GoogleFonts.tiltWarp(
              fontSize: 18, color: AppColors.background),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.notifications_outlined,
                color: AppColors.background),
            onPressed: () {},
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Tag Management',
              style: GoogleFonts.tiltWarp(
                  fontSize: 13, color: AppColors.textPrimary),
            ),
            const SizedBox(height: 14),

            /*_HubCard(
              icon: Icons.nfc,
              title: 'Write NFC Chip',
              subtitle:
              'Select a registered collar tag and encode it onto an NFC chip.',
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => const AdminNfc()),
              ),
            ),
            const SizedBox(height: 12),*/

            _HubCard(
              icon: Icons.qr_code_2,
              title: 'Generate QR Code',
              subtitle:
              'Create and share a scannable QR card for any pet collar tag.',
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => const AdminQrGeneratorScreen()),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HubCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _HubCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: AppColors.tearspwn.withOpacity(0.15),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.slaterspwn),
        ),
        child: Row(
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: AppColors.yellowrspwn.withOpacity(0.25),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, size: 26, color: AppColors.textPrimary),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: GoogleFonts.tiltWarp(
                          fontSize: 15, color: AppColors.textPrimary)),
                  const SizedBox(height: 4),
                  Text(subtitle,
                      style: GoogleFonts.zain(
                          fontSize: 13, color: AppColors.textSecondary)),
                ],
              ),
            ),
            const SizedBox(width: 8),
            const Icon(Icons.chevron_right,
                color: AppColors.textPrimary, size: 22),
          ],
        ),
      ),
    );
  }
}
