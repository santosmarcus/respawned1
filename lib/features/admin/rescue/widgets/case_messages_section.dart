import 'package:flutter/material.dart';

import 'package:respawnd1/features/admin/rescue/widgets/section_card.dart';
import 'package:respawnd1/features/rescue/widgets/case_chat.dart';

/// Case Messages on Rescue Details: the same thread, and the same chat, as
/// Track Case for staff and for the reporter (CaseChat over
/// `cases/{caseId}/messages`): suggested replies, asking the reporter for
/// the animal's location, and the community-report confirmations.
class CaseMessagesSection extends StatelessWidget {
  final String caseId;
  const CaseMessagesSection({super.key, required this.caseId});

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      title: 'Messages',
      child: CaseChat(caseId: caseId, staff: true),
    );
  }
}
