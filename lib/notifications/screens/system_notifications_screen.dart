import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:logger/logger.dart';
import 'package:cmms/notifications/services/notification_service.dart';
import 'package:cmms/notifications/screens/notification_setup_screen.dart';
import 'package:cmms/notifications/screens/notification_status_screen.dart';
import 'package:cmms/notifications/screens/notification_settings_screen.dart';

class SystemNotificationsScreen extends StatefulWidget {
  const SystemNotificationsScreen({super.key});

  @override
  State<SystemNotificationsScreen> createState() => _SystemNotificationsScreenState();
}

class _SystemNotificationsScreenState extends State<SystemNotificationsScreen> {
  final Logger _logger = Logger(printer: PrettyPrinter());
  final NotificationService _notificationService = NotificationService();
  
  bool _autoNotificationsEnabled = false;
  DateTime _defaultLastInspectionDate = DateTime(DateTime.now().year, 1, 1);
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    try {
      final autoEnabled = await _notificationService.areAutoNotificationsEnabled();
      final defaultDate = await _notificationService.getDefaultLastInspectionDate();
      
      if (mounted) {
        setState(() {
          _autoNotificationsEnabled = autoEnabled;
          _defaultLastInspectionDate = defaultDate;
          _isLoading = false;
        });
      }
    } catch (e) {
      _logger.e('Error loading settings: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _toggleAutoNotifications(bool enabled) async {
    try {
      await _notificationService.setAutoNotificationsEnabled(enabled);
      setState(() {
        _autoNotificationsEnabled = enabled;
      });
      
      _showSnackBar(
        enabled 
            ? 'Automatic notifications enabled' 
            : 'Automatic notifications disabled',
        enabled ? Colors.green : Colors.orange,
      );
    } catch (e) {
      _logger.e('Error toggling auto notifications: $e');
      _showSnackBar('Error updating automatic notifications: $e', Colors.red);
    }
  }

  Future<void> _updateDefaultDate() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _defaultLastInspectionDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      helpText: 'Select Default Last Inspection Date',
      cancelText: 'Cancel',
      confirmText: 'Update',
    );
    
    if (picked != null) {
      try {
        await _notificationService.setDefaultLastInspectionDate(picked);
        setState(() {
          _defaultLastInspectionDate = picked;
        });
        _showSnackBar('Default inspection date updated', Colors.green);
      } catch (e) {
        _logger.e('Error updating default date: $e');
        _showSnackBar('Error updating date: $e', Colors.red);
      }
    }
  }

  Future<void> _sendTestNotification() async {
    final String? audience = await _showAudienceDialog();
    if (audience == null) return;

    try {
      await _notificationService.triggerTestNotification(targetAudience: audience);
      _showSnackBar('Test notification sent successfully!', Colors.green);
    } catch (e) {
      _logger.e('Error sending test notification: $e');
      _showSnackBar('Error sending test notification: $e', Colors.red);
    }
  }

  Future<String?> _showAudienceDialog() async {
    return await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Select Audience', style: GoogleFonts.poppins()),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: Text('Technicians Only', style: GoogleFonts.poppins()),
              onTap: () => Navigator.pop(context, 'technicians'),
            ),
            ListTile(
              title: Text('Admins Only', style: GoogleFonts.poppins()),
              onTap: () => Navigator.pop(context, 'admins'),
            ),
            ListTile(
              title: Text('Both Technicians & Admins', style: GoogleFonts.poppins()),
              onTap: () => Navigator.pop(context, 'both'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel', style: GoogleFonts.poppins()),
          ),
        ],
      ),
    );
  }

  void _showSnackBar(String message, Color color) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message, style: GoogleFonts.poppins()),
          backgroundColor: color,
        ),
      );
    }
  }

  String _formatDate(DateTime date) {
    return '${date.day}/${date.month}/${date.year}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          'System Notifications',
          style: GoogleFonts.poppins(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
        backgroundColor: Colors.blueGrey,
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings, color: Colors.white),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const NotificationSettingsScreen(),
                ),
              );
            },
            tooltip: 'Notification Settings',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Header
                  Text(
                    'Notification Management',
                    style: GoogleFonts.poppins(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: Colors.blueGrey[800],
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Manage custom notifications, automatic scheduling, and testing',
                    style: GoogleFonts.poppins(
                      color: Colors.grey[600],
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Custom Notifications Card
                  Card(
                    elevation: 4,
                    child: Padding(
                      padding: const EdgeInsets.all(20.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.edit_notifications, color: Colors.blue[700], size: 28),
                              const SizedBox(width: 12),
                              Text(
                                'Custom Notifications',
                                style: GoogleFonts.poppins(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.blueGrey[800],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'Set up notifications for specific tasks and categories with custom schedules',
                            style: GoogleFonts.poppins(
                              color: Colors.grey[600],
                              fontSize: 14,
                            ),
                          ),
                          const SizedBox(height: 16),
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton.icon(
                              onPressed: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) => const NotificationSetupScreen(),
                                  ),
                                );
                              },
                              icon: const Icon(Icons.add_alert),
                              label: Text(
                                'Setup Custom Notification',
                                style: GoogleFonts.poppins(fontWeight: FontWeight.bold),
                              ),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.blue,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(vertical: 16),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 16),

                  // Automatic Notifications Card
                  Card(
                    elevation: 4,
                    child: Padding(
                      padding: const EdgeInsets.all(20.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.autorenew, color: Colors.green[700], size: 28),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  'Automatic Notifications',
                                  style: GoogleFonts.poppins(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.blueGrey[800],
                                  ),
                                ),
                              ),
                              Switch(
                                value: _autoNotificationsEnabled,
                                onChanged: _toggleAutoNotifications,
                                activeColor: Colors.green,
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Text(
                            _autoNotificationsEnabled
                                ? 'Automatic notifications are enabled. The system will continuously schedule and send maintenance reminders.'
                                : 'Enable automatic notifications to have the system automatically schedule maintenance reminders based on task frequencies.',
                            style: GoogleFonts.poppins(
                              color: Colors.grey[600],
                              fontSize: 14,
                            ),
                          ),
                          const SizedBox(height: 16),
                          
                          // Default Date Setting
                          Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: Colors.grey[50],
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.grey[300]!),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Default Last Inspection Date',
                                  style: GoogleFonts.poppins(
                                    fontWeight: FontWeight.bold,
                                    color: Colors.grey[800],
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        'Current: ${_formatDate(_defaultLastInspectionDate)}',
                                        style: GoogleFonts.poppins(
                                          color: Colors.grey[700],
                                        ),
                                      ),
                                    ),
                                    ElevatedButton.icon(
                                      onPressed: _updateDefaultDate,
                                      icon: const Icon(Icons.calendar_today, size: 16),
                                      label: Text(
                                        'Change',
                                        style: GoogleFonts.poppins(fontSize: 12),
                                      ),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: Colors.blueGrey,
                                        foregroundColor: Colors.white,
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 12,
                                          vertical: 8,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  'This date is used as the baseline for calculating notification schedules when automatic notifications are enabled.',
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
                    ),
                  ),

                  const SizedBox(height: 16),

                  // Test Notifications Card
                  Card(
                    elevation: 4,
                    child: Padding(
                      padding: const EdgeInsets.all(20.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.send, color: Colors.orange[700], size: 28),
                              const SizedBox(width: 12),
                              Text(
                                'Test Notifications',
                                style: GoogleFonts.poppins(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.blueGrey[800],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'Send test notifications to verify the notification system is working correctly',
                            style: GoogleFonts.poppins(
                              color: Colors.grey[600],
                              fontSize: 14,
                            ),
                          ),
                          const SizedBox(height: 16),
                          Row(
                            children: [
                              Expanded(
                                child: ElevatedButton.icon(
                                  onPressed: _sendTestNotification,
                                  icon: const Icon(Icons.send),
                                  label: Text(
                                    'Send Test Notification',
                                    style: GoogleFonts.poppins(fontWeight: FontWeight.bold),
                                  ),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.orange,
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(vertical: 16),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              ElevatedButton.icon(
                                onPressed: () => _showTestNotificationsDialog(),
                                icon: const Icon(Icons.list),
                                label: Text(
                                  'View Tests',
                                  style: GoogleFonts.poppins(),
                                ),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.grey[600],
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 16,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 16),

                  // Quick Actions Card
                  Card(
                    elevation: 4,
                    child: Padding(
                      padding: const EdgeInsets.all(20.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Quick Actions',
                            style: GoogleFonts.poppins(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Colors.blueGrey[800],
                            ),
                          ),
                          const SizedBox(height: 16),
                          Row(
                            children: [
                              Expanded(
                                child: ElevatedButton.icon(
                                  onPressed: () {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (context) => const NotificationStatusScreen(),
                                      ),
                                    );
                                  },
                                  icon: const Icon(Icons.analytics),
                                  label: Text(
                                    'View Status',
                                    style: GoogleFonts.poppins(),
                                  ),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.blueGrey,
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(vertical: 12),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: ElevatedButton.icon(
                                  onPressed: () {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (context) => const NotificationSettingsScreen(),
                                      ),
                                    );
                                  },
                                  icon: const Icon(Icons.settings),
                                  label: Text(
                                    'Settings',
                                    style: GoogleFonts.poppins(),
                                  ),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.grey[600],
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(vertical: 12),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 24),

                  // Information Card
                  Card(
                    elevation: 2,
                    color: Colors.blue[50],
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        children: [
                          Row(
                            children: [
                              Icon(Icons.info_outline, color: Colors.blue[700]),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  'System Information',
                                  style: GoogleFonts.poppins(
                                    fontWeight: FontWeight.bold,
                                    color: Colors.blue[700],
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Text(
                            '• Notifications are sent at 9:00 AM and 11:00 AM (if 9 AM fails)\n'
                            '• Automatic notifications cycle continuously based on task frequencies\n'
                            '• Test notifications can be deleted from the test list\n'
                            '• All users receive notifications (not just technicians)\n'
                            '• Notifications work like WhatsApp - wake screen, use device settings',
                            style: GoogleFonts.poppins(
                              fontSize: 13,
                              color: Colors.blue[700],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  void _showTestNotificationsDialog() {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        child: Container(
          width: MediaQuery.of(context).size.width * 0.8,
          height: MediaQuery.of(context).size.height * 0.6,
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Row(
                children: [
                  Text(
                    'Test Notifications',
                    style: GoogleFonts.poppins(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Expanded(
                child: StreamBuilder<List<Map<String, dynamic>>>(
                  stream: _notificationService.getTestNotifications(),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    
                    final testNotifications = snapshot.data ?? [];
                    
                    if (testNotifications.isEmpty) {
                      return Center(
                        child: Text(
                          'No test notifications found',
                          style: GoogleFonts.poppins(color: Colors.grey[600]),
                        ),
                      );
                    }
                    
                    return ListView.builder(
                      itemCount: testNotifications.length,
                      itemBuilder: (context, index) {
                        final notification = testNotifications[index];
                        return Card(
                          child: ListTile(
                            leading: const Icon(Icons.send, color: Colors.orange),
                            title: Text(
                              notification['title'] ?? 'Test Notification',
                              style: GoogleFonts.poppins(fontWeight: FontWeight.bold),
                            ),
                            subtitle: Text(
                              'Target: ${notification['targetAudience'] ?? 'Unknown'}',
                              style: GoogleFonts.poppins(fontSize: 12),
                            ),
                            trailing: IconButton(
                              onPressed: () async {
                                try {
                                  await _notificationService.deleteTestNotification(notification['id']);
                                  _showSnackBar('Test notification deleted', Colors.green);
                                } catch (e) {
                                  _showSnackBar('Error deleting notification: $e', Colors.red);
                                }
                              },
                              icon: const Icon(Icons.delete, color: Colors.red),
                              tooltip: 'Delete Test Notification',
                            ),
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
