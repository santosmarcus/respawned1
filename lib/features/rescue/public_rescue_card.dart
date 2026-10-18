import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../app_theme.dart';
import 'package:respawnd1/core/utils/case_id.dart';
import 'track_case_page.dart';
import 'public_rescue_item.dart';
import 'package:respawnd1/features/adoption/community_adoption_track_page.dart';

class PublicRescueCard extends StatelessWidget {
  final PublicRescueItem item;
  final double? distanceKm;

  const PublicRescueCard({super.key, required this.item, this.distanceKm});

  String get _dateLabel {
    final d = item.createdAt;
    if (d == null) return '-';
    const months = [
      '', 'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December'
    ];
    final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
    final ampm = d.hour < 12 ? 'AM' : 'PM';
    final min = d.minute.toString().padLeft(2, '0');
    return '${months[d.month]} ${d.day}, ${d.year} $h:$min $ampm';
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => item.isCommunityAdoptionEligible
                ? CommunityAdoptionTrackPage(caseId: item.caseId)
                : TrackCasePage(caseId: item.caseId, initialTabIndex: 0),
          ),
        );
      },
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: AppColors.background,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: AppColors.slaterspwn,
              blurRadius: 1,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: item.photoUrls.isNotEmpty
                  ? Image.network(
                item.photoUrls.first,
                width: 100,
                height: 100,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => _placeholderThumb(),
              )
                  : _placeholderThumb(),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '#${shortCaseId(item.caseId)}',
                    style: GoogleFonts.tiltWarp(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(children: [
                    const Icon(Icons.calendar_today, size: 12, color: AppColors.textSecondary),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(_dateLabel,
                          style: GoogleFonts.zain(fontSize: 12, color: AppColors.textSecondary)),
                    ),
                  ]),
                  const SizedBox(height: 4),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.location_on_outlined, size: 12, color: AppColors.textSecondary),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          item.address,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.zain(fontSize: 12, color: AppColors.textPrimary),
                        ),
                      ),
                    ],
                  ),
                  if (distanceKm != null) ...[
                    const SizedBox(height: 4),
                    Row(children: [
                      const Icon(Icons.social_distance, size: 12, color: AppColors.textSecondary),
                      const SizedBox(width: 6),
                      Text(
                        distanceKm! < 1
                            ? '${(distanceKm! * 1000).round()} m away'
                            : '${distanceKm!.toStringAsFixed(1)} km away',
                        style: GoogleFonts.zain(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: distanceKm! <= 5
                              ? AppColors.greenrspwn
                              : AppColors.textSecondary,
                        ),
                      ),
                    ]),
                  ],
                  const SizedBox(height: 4),
                  if (item.animalType.isNotEmpty)
                    Row(children: [
                      const Icon(Icons.pets, size: 12, color: AppColors.textSecondary),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          item.animalType,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.zain(fontSize: 12, color: AppColors.textPrimary),
                        ),
                      ),
                    ]),
                  const SizedBox(height: 4),
                  Row(children: [
                    const Icon(Icons.info_outline, size: 12, color: AppColors.textSecondary),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        item.latestStatusLabel,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.zain(fontSize: 12, color: AppColors.textPrimary),
                      ),
                    ),
                  ]),
                  const SizedBox(height: 4),
                  Row(children: [
                    const Icon(Icons.circle, size: 8, color: AppColors.slaterspwn),
                    const SizedBox(width: 8),
                    Text(item.reporterTag,
                        style: GoogleFonts.zain(fontSize: 11, color: AppColors.textSecondary)),
                  ]),
                  if (item.isCommunityAdoptionEligible) ...[
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppColors.greenrspwn.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.favorite, size: 12, color: AppColors.greenrspwn),
                          const SizedBox(width: 4),
                          Text('This animal is open for adoption.',
                              style: GoogleFonts.zain(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.greenrspwn)),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _placeholderThumb() {
    return Container(
      width: 64,
      height: 64,
      color: AppColors.slaterspwn,
      child: const Icon(Icons.image_outlined, color: AppColors.textSecondary),
    );
  }
}