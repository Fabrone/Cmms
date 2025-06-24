import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
//import 'package:logger/logger.dart';
import 'package:cmms/notifications/services/notification_service.dart';
import 'package:cmms/notifications/models/notification_model.dart';
import 'package:cmms/notifications/screens/notification_detail_screen.dart';
import 'package:intl/intl.dart';

class NotificationSetupTrackingScreen extends StatefulWidget {
  const NotificationSetupTrackingScreen({super.key});

  @override
  State<NotificationSetupTrackingScreen> createState() => _NotificationSetupTrackingScreenState();
}

class _NotificationSetupTrackingScreenState extends State<NotificationSetupTrackingScreen>
    with SingleTickerProviderStateMixin {
  //final Logger _logger = Logger(printer: PrettyPrinter());
  final NotificationService _notificationService = NotificationService();
  
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Notification Tracking',
          style: GoogleFonts.poppins(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
        backgroundColor: Colors.blueGrey,
        iconTheme: const IconThemeData(color: Colors.white),
        bottom: TabBar(
          controller: _tabController,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          indicatorColor: Colors.white,
          labelStyle: GoogleFonts.poppins(fontWeight: FontWeight.bold),
          unselectedLabelStyle: GoogleFonts.poppins(),
          tabs: const [
            Tab(text: 'Setup'),
            Tab(text: 'Pending'),
            Tab(text: 'Received'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildSetupTab(),
          _buildPendingTab(),
          _buildReceivedTab(),
        ],
      ),
    );
  }

  Widget _buildSetupTab() {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionHeader(
            'Setup Notifications',
            'All notifications that have been configured',
            Icons.settings,
            Colors.blue,
          ),
          const SizedBox(height: 16),
          Expanded(
            child: StreamBuilder<List<GroupedNotificationModel>>(
              stream: _notificationService.getSetupNotifications(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                
                if (snapshot.hasError) {
                  return _buildErrorWidget('Error loading setup notifications: ${snapshot.error}');
                }
                
                final notifications = snapshot.data ?? [];
                
                if (notifications.isEmpty) {
                  return _buildEmptyWidget(
                    'No notifications setup',
                    'No notifications have been configured yet. Use the notification setup screen to create some.',
                    Icons.settings,
                  );
                }
                
                return _buildNotificationsList(notifications, 'setup');
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPendingTab() {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionHeader(
            'Pending Notifications',
            'Notifications waiting to be sent',
            Icons.schedule_send,
            Colors.orange,
          ),
          const SizedBox(height: 16),
          Expanded(
            child: StreamBuilder<List<GroupedNotificationModel>>(
              stream: _notificationService.getPendingNotifications(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                
                if (snapshot.hasError) {
                  return _buildErrorWidget('Error loading pending notifications: ${snapshot.error}');
                }
                
                final notifications = snapshot.data ?? [];
                
                if (notifications.isEmpty) {
                  return _buildEmptyWidget(
                    'No pending notifications',
                    'All notifications have been sent or there are no notifications scheduled.',
                    Icons.schedule_send,
                  );
                }
                
                return _buildNotificationsList(notifications, 'pending');
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildReceivedTab() {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionHeader(
            'Received Notifications',
            'Notifications that have been sent and received',
            Icons.mark_email_read,
            Colors.green,
          ),
          const SizedBox(height: 16),
          Expanded(
            child: StreamBuilder<List<GroupedNotificationModel>>(
              stream: _notificationService.getReceivedNotifications(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                
                if (snapshot.hasError) {
                  return _buildErrorWidget('Error loading received notifications: ${snapshot.error}');
                }
                
                final notifications = snapshot.data ?? [];
                
                if (notifications.isEmpty) {
                  return _buildEmptyWidget(
                    'No received notifications',
                    'No notifications have been sent yet.',
                    Icons.mark_email_read,
                  );
                }
                
                return _buildNotificationsList(notifications, 'received');
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title, String subtitle, IconData icon, Color color) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: color, size: 24),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: GoogleFonts.poppins(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.blueGrey[800],
                ),
              ),
              Text(
                subtitle,
                style: GoogleFonts.poppins(
                  fontSize: 12,
                  color: Colors.grey[600],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildNotificationsList(List<GroupedNotificationModel> notifications, String type) {
    return ListView.builder(
      itemCount: notifications.length,
      itemBuilder: (context, index) {
        final notification = notifications[index];
        return _buildNotificationCard(notification, type);
      },
    );
  }

  Widget _buildNotificationCard(GroupedNotificationModel notification, String type) {
    final categories = notification.notifications.map((n) => n.category).toSet().toList();
    final now = DateTime.now();
    final isOverdue = notification.notificationDate.isBefore(now) && !notification.isTriggered;
    final isDueToday = DateFormat.yMd().format(notification.notificationDate) == 
                      DateFormat.yMd().format(now);
    
    Color statusColor;
    String statusText;
    IconData statusIcon;
    
    if (notification.isTriggered) {
      if (notification.readByUsers.isNotEmpty) {
        statusColor = Colors.green;
        statusText = 'Read';
        statusIcon = Icons.mark_email_read;
      } else {
        statusColor = Colors.blue;
        statusText = 'Sent';
        statusIcon = Icons.send;
      }
    } else if (isOverdue) {
      statusColor = Colors.red;
      statusText = 'Overdue';
      statusIcon = Icons.error;
    } else if (isDueToday) {
      statusColor = Colors.orange;
      statusText = 'Due Today';
      statusIcon = Icons.schedule;
    } else {
      statusColor = Colors.blueGrey;
      statusText = 'Scheduled';
      statusIcon = Icons.schedule_send;
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 2,
      child: InkWell(
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => NotificationDetailScreen(notification: notification),
            ),
          );
        },
        borderRadius: BorderRadius.circular(8),
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
                        Icon(statusIcon, color: Colors.white, size: 16),
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
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyWidget(String title, String subtitle, IconData icon) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 64, color: Colors.grey[400]),
          const SizedBox(height: 16),
          Text(
            title,
            style: GoogleFonts.poppins(
              fontSize: 18,
              color: Colors.grey[600],
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Text(
              subtitle,
              style: GoogleFonts.poppins(
                color: Colors.grey[500],
                fontSize: 14,
              ),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorWidget(String error) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.error_outline, size: 64, color: Colors.red[400]),
          const SizedBox(height: 16),
          Text(
            'Error Loading Data',
            style: GoogleFonts.poppins(
              fontSize: 18,
              color: Colors.red[600],
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Text(
              error,
              style: GoogleFonts.poppins(
                color: Colors.red[500],
                fontSize: 14,
              ),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }
}
