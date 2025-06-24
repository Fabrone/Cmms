import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cmms/notifications/services/notification_service.dart';
import 'package:cmms/notifications/models/notification_model.dart';
import 'package:cmms/notifications/screens/notification_detail_screen.dart';
import 'package:intl/intl.dart';

class NotificationStatusScreen extends StatefulWidget {
  const NotificationStatusScreen({super.key});

  @override
  State<NotificationStatusScreen> createState() => _NotificationStatusScreenState();
}

class _NotificationStatusScreenState extends State<NotificationStatusScreen>
    with SingleTickerProviderStateMixin {
  final NotificationService _notificationService = NotificationService();
  
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
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
          'Notification Status',
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
            Tab(text: 'Upcoming'),
            Tab(text: 'Sent'),
            Tab(text: 'Received'),
            Tab(text: 'All'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildUpcomingTab(),
          _buildSentTab(),
          _buildReceivedTab(),
          _buildAllTab(),
        ],
      ),
    );
  }

  Widget _buildUpcomingTab() {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionHeader(
            'Upcoming Notifications',
            'Scheduled notifications that haven\'t been sent yet',
            Icons.schedule_send,
            Colors.blue,
          ),
          const SizedBox(height: 16),
          Expanded(
            child: StreamBuilder<List<GroupedNotificationModel>>(
              stream: _notificationService.getUpcomingNotifications(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                
                if (snapshot.hasError) {
                  return _buildErrorWidget('Error loading upcoming notifications: ${snapshot.error}');
                }
                
                final notifications = snapshot.data ?? [];
                
                if (notifications.isEmpty) {
                  return _buildEmptyWidget(
                    'No upcoming notifications',
                    'All scheduled notifications have been sent or there are no notifications set up.',
                    Icons.schedule_send,
                  );
                }
                
                return _buildNotificationsList(notifications, 'upcoming');
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSentTab() {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionHeader(
            'Sent Notifications',
            'Notifications that have been successfully sent to users',
            Icons.send,
            Colors.green,
          ),
          const SizedBox(height: 16),
          Expanded(
            child: StreamBuilder<List<GroupedNotificationModel>>(
              stream: _notificationService.getSentNotifications(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                
                if (snapshot.hasError) {
                  return _buildErrorWidget('Error loading sent notifications: ${snapshot.error}');
                }
                
                final notifications = snapshot.data ?? [];
                
                if (notifications.isEmpty) {
                  return _buildEmptyWidget(
                    'No sent notifications',
                    'No notifications have been sent yet.',
                    Icons.send,
                  );
                }
                
                return _buildNotificationsList(notifications, 'sent');
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
            'Notifications that have been read by users',
            Icons.mark_email_read,
            Colors.orange,
          ),
          const SizedBox(height: 16),
          Expanded(
            child: StreamBuilder<List<GroupedNotificationModel>>(
              stream: _notificationService.getReceivedReadNotifications(),
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
                    'No notifications have been read by users yet.',
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

  Widget _buildAllTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionHeader(
            'All Notifications',
            'Complete overview of all notifications in the system',
            Icons.list_alt,
            Colors.blueGrey,
          ),
          const SizedBox(height: 16),
          StreamBuilder<List<GroupedNotificationModel>>(
            stream: _notificationService.getAllNotifications(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const SizedBox(
                  height: 200,
                  child: Center(child: CircularProgressIndicator()),
                );
              }
              
              if (snapshot.hasError) {
                return SizedBox(
                  height: 200,
                  child: _buildErrorWidget('Error loading notifications: ${snapshot.error}'),
                );
              }
              
              final notifications = snapshot.data ?? [];
              
              if (notifications.isEmpty) {
                return SizedBox(
                  height: 200,
                  child: _buildEmptyWidget(
                    'No notifications found',
                    'No notifications have been set up in the system yet.',
                    Icons.notifications_none,
                  ),
                );
              }
              
              return Column(
                children: [
                  _buildStatisticsCard(notifications),
                  const SizedBox(height: 16),
                  
                  // Section Header for Notifications List
                  Row(
                    children: [
                      Icon(Icons.list, color: Colors.blueGrey[700], size: 20),
                      const SizedBox(width: 8),
                      Text(
                        'Notification Details',
                        style: GoogleFonts.poppins(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.blueGrey[800],
                        ),
                      ),
                      const Spacer(),
                      Text(
                        '${notifications.length} groups',
                        style: GoogleFonts.poppins(
                          fontSize: 12,
                          color: Colors.grey[600],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  
                  ListView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: notifications.length,
                    itemBuilder: (context, index) {
                      final notification = notifications[index];
                      return _buildNotificationCard(notification, 'all');
                    },
                  ),
                ],
              );
            },
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

  Widget _buildStatisticsCard(List<GroupedNotificationModel> notifications) {
    final upcoming = notifications.where((n) => !n.isTriggered).length;
    final sent = notifications.where((n) => n.isTriggered).length;
    final read = notifications.where((n) => n.readByUsers.isNotEmpty).length;
    final totalTasks = notifications.fold<int>(0, (sum, n) => sum + n.notifications.length);

    return Card(
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.analytics, color: Colors.blueGrey[700], size: 20),
                const SizedBox(width: 8),
                Text(
                  'Notification Statistics',
                  style: GoogleFonts.poppins(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.blueGrey[800],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _buildStatItem('Total Groups', notifications.length.toString(), Colors.blueGrey),
                ),
                Expanded(
                  child: _buildStatItem('Total Tasks', totalTasks.toString(), Colors.blue),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _buildStatItem('Upcoming', upcoming.toString(), Colors.orange),
                ),
                Expanded(
                  child: _buildStatItem('Sent', sent.toString(), Colors.green),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _buildStatItem('Read', read.toString(), Colors.purple),
                ),
                Expanded(
                  child: _buildStatItem('Unread', (sent - read).toString(), Colors.red),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatItem(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.all(12),
      margin: const EdgeInsets.symmetric(horizontal: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        children: [
          Text(
            value,
            style: GoogleFonts.poppins(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          Text(
            label,
            style: GoogleFonts.poppins(
              fontSize: 12,
              color: color,
            ),
          ),
        ],
      ),
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
        statusText = 'Read by ${notification.readByUsers.length} user(s)';
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
              
              if (notification.isTriggered && notification.triggeredAt != null) ...[
                const SizedBox(height: 12),
                Row(
                  children: [
                    Icon(Icons.access_time, size: 16, color: Colors.grey[600]),
                    const SizedBox(width: 4),
                    Text(
                      'Sent: ${DateFormat.yMMMd().add_jm().format(notification.triggeredAt!)}',
                      style: GoogleFonts.poppins(
                        fontSize: 12,
                        color: Colors.grey[600],
                      ),
                    ),
                  ],
                ),
              ],
              
              if (notification.readByUsers.isNotEmpty) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    Icon(Icons.visibility, size: 16, color: Colors.green[600]),
                    const SizedBox(width: 4),
                    Text(
                      'Read by ${notification.readByUsers.length} user(s)',
                      style: GoogleFonts.poppins(
                        fontSize: 12,
                        color: Colors.green[600],
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ],
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
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: () {
              setState(() {
                // Trigger rebuild
              });
            },
            icon: const Icon(Icons.refresh),
            label: Text('Retry', style: GoogleFonts.poppins()),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ),
    );
  }
}