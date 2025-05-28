import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:cmms/models/notification_model.dart';
import 'package:cmms/services/notification_service.dart';

class NotificationSetupTrackingScreen extends StatelessWidget {
  const NotificationSetupTrackingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Notification Setup Tracking',
          style: GoogleFonts.poppins(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
        backgroundColor: Colors.blueGrey,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Setup Notifications Status',
              style: GoogleFonts.poppins(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Colors.blueGrey[800],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Track the status of your scheduled maintenance notifications',
              style: GoogleFonts.poppins(
                color: Colors.grey[600],
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 20),
            
            Expanded(
              child: StreamBuilder<List<GroupedNotificationModel>>(
                stream: NotificationService().getSetupNotifications(),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  
                  if (snapshot.hasError) {
                    return Center(
                      child: Text(
                        'Error: ${snapshot.error}',
                        style: GoogleFonts.poppins(),
                      ),
                    );
                  }
                  
                  final notifications = snapshot.data ?? [];
                  
                  if (notifications.isEmpty) {
                    return Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.notification_add,
                            size: 64,
                            color: Colors.grey[400],
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'No notifications setup yet',
                            style: GoogleFonts.poppins(
                              fontSize: 18,
                              color: Colors.grey[600],
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Setup notifications will appear here with their status',
                            style: GoogleFonts.poppins(
                              color: Colors.grey[500],
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    );
                  }
                  
                  return ListView.builder(
                    itemCount: notifications.length,
                    itemBuilder: (context, index) {
                      final notification = notifications[index];
                      return _buildNotificationCard(notification);
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNotificationCard(GroupedNotificationModel notification) {
    final categories = notification.notifications
        .map((n) => n.category)
        .toSet()
        .toList();
    
    final now = DateTime.now();
    final isOverdue = notification.notificationDate.isBefore(now);
    final isDueToday = DateFormat.yMd().format(notification.notificationDate) == 
                      DateFormat.yMd().format(now);
    
    Color statusColor;
    String statusText;
    IconData statusIcon;
    
    if (notification.isTriggered) {
      statusColor = Colors.green;
      statusText = 'Sent';
      statusIcon = Icons.check_circle;
    } else if (isOverdue) {
      statusColor = Colors.red;
      statusText = 'Overdue';
      statusIcon = Icons.error;
    } else if (isDueToday) {
      statusColor = Colors.orange;
      statusText = 'Due Today';
      statusIcon = Icons.schedule;
    } else {
      statusColor = Colors.blue;
      statusText = 'Scheduled';
      statusIcon = Icons.schedule_send;
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: statusColor,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        statusIcon,
                        color: Colors.white,
                        size: 16,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        statusText,
                        style: GoogleFonts.poppins(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                const Spacer(),
                Text(
                  DateFormat.yMMMd().format(notification.notificationDate),
                  style: GoogleFonts.poppins(
                    fontWeight: FontWeight.bold,
                    color: Colors.grey[700],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            
            Text(
              '${notification.notifications.length} tasks in ${categories.length} categories',
              style: GoogleFonts.poppins(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Colors.grey[800],
              ),
            ),
            const SizedBox(height: 8),
            
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: categories.map((category) => Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.blueGrey[50],
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.blueGrey[200]!),
                ),
                child: Text(
                  category,
                  style: GoogleFonts.poppins(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: Colors.blueGrey[700],
                  ),
                ),
              )).toList(),
            ),
            
            const SizedBox(height: 12),
            
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey[50],
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.grey[200]!),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.info_outline,
                    size: 16,
                    color: Colors.grey[600],
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      notification.isTriggered
                          ? 'Notification has been sent to technicians'
                          : 'Notification will be sent at 9:00 AM on the scheduled date',
                      style: GoogleFonts.poppins(
                        fontSize: 12,
                        color: Colors.grey[600],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
