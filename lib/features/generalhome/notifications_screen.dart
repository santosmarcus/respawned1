import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:respawnd1/app_theme.dart';
import 'package:respawnd1/features/generalhome/home_screen.dart';
import 'package:respawnd1/features/generalhome/user_profile.dart';

class _Notification {
  final String caseID;
  final String type;
  final String message;
  final String time;
  final bool hasUnread;

  const _Notification({

    required this.caseID,
    required this.type,
    required this.message,
    required this.time,
    this.hasUnread = false,
  });
}


class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {


//sample
  final List<_Notification> _notifications = [
    const _Notification(
      caseID: '#123ABCD',
      type: 'Status Update',
      message: 'Searching for Pet Transporter',
      time: '5 minutes ago',
      hasUnread: true,),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        elevation: 0,
        scrolledUnderElevation: 0,
        automaticallyImplyLeading: false,
        centerTitle: true,
        toolbarHeight: 80,
        title: Text(
          'Notifications',
          style: GoogleFonts.tiltWarp(
            fontSize: 22,
            fontWeight: FontWeight.bold,
            color: AppColors.textPrimary,
          ),
        ),
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: 1,
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.home_outlined),
            activeIcon: Icon(Icons.home),
            label: 'Home',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.notifications_outlined),
            activeIcon: Icon(Icons.notifications),
            label: 'Notifications',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.person_outline),
            activeIcon: Icon(Icons.person),
            label: 'My Profile',
          ),
        ],
        onTap: (index) {
          if (index == 0) {
            if (Navigator.canPop(context)) {
              Navigator.pop(context);
            } else {
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(builder: (context) => const HomeScreen()),
              );
            }
          } else if (index == 2) {
            Navigator.pushReplacement(
              context, MaterialPageRoute(builder: (_) => const UserProfile()),
            );
          }
        },
      ),

      body: _notifications.isEmpty
          ? Center(
        child: Text(
          'No notifications yet.',
          style: GoogleFonts.zain(
            fontSize: 15,
            color: AppColors.textSecondary,
          ),
        ),
      )
          : ListView.builder(
        padding: const EdgeInsets.symmetric(horizontal: 35, vertical: 12),
        itemCount: _notifications.length,
        itemBuilder: (context, index) {
          final notif = _notifications[index];
          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _NotificationTile(notification: notif),
          );
        },
      ),
    );
  }
}
  class _NotificationTile extends StatelessWidget {
    final _Notification notification;
    const _NotificationTile({required this.notification});

      @override
      Widget build(BuildContext context) {
        return Container(
          decoration: BoxDecoration(
            color: AppColors.background,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(color: Colors.grey.withOpacity(0.5),
              blurRadius: 15,
              offset: const Offset(0.0, 0.75),),
            ]
          ),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                      Text(
                        '${notification.caseID} | ${notification.type}',
                        style: GoogleFonts.tiltWarp(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textPrimary,
                        ),
                      ),

                        const SizedBox(height: 4),
                    Text(
                      notification.message,
                      style: GoogleFonts.zain(
                      fontSize: 13,
                      color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                 ),
                ),

      const SizedBox(width: 8),

        // Time + unread dot
        Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                notification.time,
                style: GoogleFonts.zain(
                fontSize: 11,
                color: AppColors.textSecondary,
                ),
              ),
             if (notification.hasUnread) ...[
               const SizedBox(height: 4),
                Container(
                  width: 8,
                  height: 8,
                  decoration: const BoxDecoration(
                  color: Colors.redAccent,
                  shape: BoxShape.circle,
                  ),
                ),
              ],
            ],
           ),
          ],
        ),
      );
    }
  }