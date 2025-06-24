import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:logger/logger.dart';
import 'package:cmms/notifications/models/notification_model.dart';
import 'package:cmms/notifications/services/notification_service.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';

class NotificationDetailScreen extends StatefulWidget {
  final GroupedNotificationModel notification;

  const NotificationDetailScreen({
    super.key,
    required this.notification,
  });

  @override
  State<NotificationDetailScreen> createState() => _NotificationDetailScreenState();
}

class _NotificationDetailScreenState extends State<NotificationDetailScreen> {
  final Logger _logger = Logger(printer: PrettyPrinter());
  final NotificationService _notificationService = NotificationService();
  
  bool _isMarkedAsRead = false;

  @override
  void initState() {
    super.initState();
    _markAsReadIfNeeded();
  }

  Future<void> _markAsReadIfNeeded() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null && widget.notification.isTriggered) {
      try {
        await _notificationService.markNotificationAsReadByUser(
          widget.notification.id,
          user.uid,
        );
        setState(() {
          _isMarkedAsRead = true;
        });
      } catch (e) {
        _logger.e('Error marking notification as read: $e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final categories = widget.notification.notifications.map((n) => n.category).toSet().toList();
    final now = DateTime.now();
    final isOverdue = widget.notification.notificationDate.isBefore(now) && !widget.notification.isTriggered;
    final isDueToday = DateFormat.yMd().format(widget.notification.notificationDate) == 
                      DateFormat.yMd().format(now);
    
    Color statusColor;
    String statusText;
    IconData statusIcon;
    
    if (widget.notification.isTriggered) {
      if (widget.notification.readByUsers.isNotEmpty || _isMarkedAsRead) {
        statusColor = Colors.green;
        statusText = 'Received & Read';
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

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Notification Details',
          style: GoogleFonts.poppins(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
        backgroundColor: Colors.blueGrey,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Status Card
            Card(
              elevation: 4,
              child: Padding(
                padding: const EdgeInsets.all(20.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: statusColor,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Icon(statusIcon, color: Colors.white, size: 24),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                statusText,
                                style: GoogleFonts.poppins(
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                  color: statusColor,
                                ),
                              ),
                              Text(
                                DateFormat.yMMMd().format(widget.notification.notificationDate),
                                style: GoogleFonts.poppins(
                                  color: Colors.grey[600],
                                  fontSize: 14,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    
                    Row(
                      children: [
                        _buildInfoChip(
                          '${widget.notification.notifications.length}',
                          'Tasks',
                          Colors.blue,
                        ),
                        const SizedBox(width: 12),
                        _buildInfoChip(
                          '${categories.length}',
                          'Categories',
                          Colors.green,
                        ),
                        const SizedBox(width: 12),
                        _buildInfoChip(
                          '${widget.notification.readByUsers.length}',
                          'Read by',
                          Colors.purple,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 16),

            // Timeline Card
            if (widget.notification.isTriggered) ...[
              Card(
                elevation: 4,
                child: Padding(
                  padding: const EdgeInsets.all(20.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Timeline',
                        style: GoogleFonts.poppins(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.blueGrey[800],
                        ),
                      ),
                      const SizedBox(height: 16),
                      
                      _buildTimelineItem(
                        'Scheduled',
                        DateFormat.yMMMd().add_jm().format(widget.notification.notificationDate),
                        Icons.schedule_send,
                        Colors.blueGrey,
                        isCompleted: true,
                      ),
                      
                      if (widget.notification.triggeredAt != null)
                        _buildTimelineItem(
                          'Sent',
                          DateFormat.yMMMd().add_jm().format(widget.notification.triggeredAt!),
                          Icons.send,
                          Colors.blue,
                          isCompleted: true,
                        ),
                      
                      if (widget.notification.readByUsers.isNotEmpty || _isMarkedAsRead)
                        _buildTimelineItem(
                          'Read',
                          widget.notification.readByUsers.isNotEmpty
                              ? DateFormat.yMMMd().add_jm().format(widget.notification.readByUsers.first.readAt)
                              : 'Just now',
                          Icons.mark_email_read,
                          Colors.green,
                          isCompleted: true,
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ],

            // Categories Card
            Card(
              elevation: 4,
              child: Padding(
                padding: const EdgeInsets.all(20.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Categories',
                      style: GoogleFonts.poppins(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.blueGrey[800],
                      ),
                    ),
                    const SizedBox(height: 16),
                    
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: categories.map((category) {
                        final categoryTasks = widget.notification.notifications
                            .where((n) => n.category == category)
                            .toList();
                        
                        return Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(
                            color: Colors.blueGrey[50],
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.blueGrey[200]!),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                category,
                                style: GoogleFonts.poppins(
                                  fontWeight: FontWeight.bold,
                                  color: Colors.blueGrey[700],
                                ),
                              ),
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: Colors.blueGrey[200],
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  '${categoryTasks.length}',
                                  style: GoogleFonts.poppins(
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.blueGrey[700],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );
                      }).toList(),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 16),

            // Tasks List Card
            Card(
              elevation: 4,
              child: Padding(
                padding: const EdgeInsets.all(20.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Maintenance Tasks',
                      style: GoogleFonts.poppins(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.blueGrey[800],
                      ),
                    ),
                    const SizedBox(height: 16),
                    
                    ListView.separated(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: widget.notification.notifications.length,
                      separatorBuilder: (context, index) => const Divider(),
                      itemBuilder: (context, index) {
                        final task = widget.notification.notifications[index];
                        return _buildTaskItem(task);
                      },
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 16),

            // Read Status Card
            if (widget.notification.readByUsers.isNotEmpty) ...[
              Card(
                elevation: 4,
                child: Padding(
                  padding: const EdgeInsets.all(20.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Read Status',
                        style: GoogleFonts.poppins(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.blueGrey[800],
                        ),
                      ),
                      const SizedBox(height: 16),
                      
                      ListView.separated(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: widget.notification.readByUsers.length,
                        separatorBuilder: (context, index) => const Divider(),
                        itemBuilder: (context, index) {
                          final readInfo = widget.notification.readByUsers[index];
                          return ListTile(
                            leading: CircleAvatar(
                              backgroundColor: Colors.green[100],
                              child: Icon(Icons.person, color: Colors.green[700]),
                            ),
                            title: Text(
                              'User ${readInfo.userId.substring(0, 8)}...',
                              style: GoogleFonts.poppins(fontWeight: FontWeight.w500),
                            ),
                            subtitle: Text(
                              'Read on ${DateFormat.yMMMd().add_jm().format(readInfo.readAt)}',
                              style: GoogleFonts.poppins(fontSize: 12),
                            ),
                            trailing: Icon(Icons.check_circle, color: Colors.green[600]),
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildInfoChip(String value, String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        children: [
          Text(
            value,
            style: GoogleFonts.poppins(
              fontSize: 18,
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

  Widget _buildTimelineItem(
    String title,
    String time,
    IconData icon,
    Color color, {
    bool isCompleted = false,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: isCompleted ? color : Colors.grey[300],
              shape: BoxShape.circle,
            ),
            child: Icon(
              icon,
              color: Colors.white,
              size: 16,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: GoogleFonts.poppins(
                    fontWeight: FontWeight.bold,
                    color: isCompleted ? color : Colors.grey[600],
                  ),
                ),
                Text(
                  time,
                  style: GoogleFonts.poppins(
                    fontSize: 12,
                    color: Colors.grey[600],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTaskItem(NotificationModel task) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.blueGrey[100],
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(
          task.category,
          style: GoogleFonts.poppins(
            fontWeight: FontWeight.bold,
            fontSize: 12,
            color: Colors.blueGrey[700],
          ),
        ),
      ),
      title: Text(
        task.component,
        style: GoogleFonts.poppins(
          fontWeight: FontWeight.w500,
          fontSize: 14,
        ),
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            task.intervention,
            style: GoogleFonts.poppins(fontSize: 12),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Icon(Icons.schedule, size: 12, color: Colors.grey[600]),
              const SizedBox(width: 4),
              Text(
                'Every ${task.frequency} months',
                style: GoogleFonts.poppins(
                  fontSize: 11,
                  color: Colors.grey[600],
                ),
              ),
              const SizedBox(width: 12),
              Icon(Icons.event, size: 12, color: Colors.grey[600]),
              const SizedBox(width: 4),
              Text(
                'Next: ${DateFormat.yMd().format(task.nextInspectionDate)}',
                style: GoogleFonts.poppins(
                  fontSize: 11,
                  color: Colors.grey[600],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
