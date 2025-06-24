import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:logger/logger.dart';
import 'package:cmms/notifications/services/notification_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class NotificationSettingsScreen extends StatefulWidget {
  const NotificationSettingsScreen({super.key});

  @override
  State<NotificationSettingsScreen> createState() => _NotificationSettingsScreenState();
}

class _NotificationSettingsScreenState extends State<NotificationSettingsScreen> {
  final Logger _logger = Logger(printer: PrettyPrinter());
  final NotificationService _notificationService = NotificationService();
  
  bool _notificationsEnabled = true;
  bool _autoNotificationsEnabled = false;
  bool _soundEnabled = true;
  bool _vibrationEnabled = true;
  bool _screenWakeEnabled = true;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      
      final notificationsEnabled = await _notificationService.areNotificationsEnabled();
      final autoNotificationsEnabled = await _notificationService.areAutoNotificationsEnabled();
      final soundEnabled = prefs.getBool('notification_sound_enabled') ?? true;
      final vibrationEnabled = prefs.getBool('notification_vibration_enabled') ?? true;
      final screenWakeEnabled = prefs.getBool('notification_screen_wake_enabled') ?? true;
      
      if (mounted) {
        setState(() {
          _notificationsEnabled = notificationsEnabled;
          _autoNotificationsEnabled = autoNotificationsEnabled;
          _soundEnabled = soundEnabled;
          _vibrationEnabled = vibrationEnabled;
          _screenWakeEnabled = screenWakeEnabled;
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

  Future<void> _updateNotificationsEnabled(bool enabled) async {
    try {
      await _notificationService.setNotificationsEnabled(enabled);
      setState(() {
        _notificationsEnabled = enabled;
      });
      
      _showSnackBar(
        enabled 
            ? 'Notifications enabled' 
            : 'Notifications disabled',
        enabled ? Colors.green : Colors.orange,
      );
    } catch (e) {
      _logger.e('Error updating notifications enabled: $e');
      _showSnackBar('Error updating notification settings: $e', Colors.red);
    }
  }

  Future<void> _updateAutoNotificationsEnabled(bool enabled) async {
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
      _logger.e('Error updating auto notifications: $e');
      _showSnackBar('Error updating automatic notifications: $e', Colors.red);
    }
  }

  Future<void> _updateSoundEnabled(bool enabled) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('notification_sound_enabled', enabled);
      setState(() {
        _soundEnabled = enabled;
      });
      
      _showSnackBar(
        enabled 
            ? 'Notification sound enabled' 
            : 'Notification sound disabled',
        enabled ? Colors.green : Colors.orange,
      );
    } catch (e) {
      _logger.e('Error updating sound setting: $e');
      _showSnackBar('Error updating sound setting: $e', Colors.red);
    }
  }

  Future<void> _updateVibrationEnabled(bool enabled) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('notification_vibration_enabled', enabled);
      setState(() {
        _vibrationEnabled = enabled;
      });
      
      _showSnackBar(
        enabled 
            ? 'Notification vibration enabled' 
            : 'Notification vibration disabled',
        enabled ? Colors.green : Colors.orange,
      );
    } catch (e) {
      _logger.e('Error updating vibration setting: $e');
      _showSnackBar('Error updating vibration setting: $e', Colors.red);
    }
  }

  Future<void> _updateScreenWakeEnabled(bool enabled) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('notification_screen_wake_enabled', enabled);
      setState(() {
        _screenWakeEnabled = enabled;
      });
      
      _showSnackBar(
        enabled 
            ? 'Screen wake enabled for urgent notifications' 
            : 'Screen wake disabled',
        enabled ? Colors.green : Colors.orange,
      );
    } catch (e) {
      _logger.e('Error updating screen wake setting: $e');
      _showSnackBar('Error updating screen wake setting: $e', Colors.red);
    }
  }

  Future<void> _resetNotificationCount() async {
    try {
      await _notificationService.resetNotificationCount();
      _showSnackBar('Notification count reset', Colors.green);
    } catch (e) {
      _logger.e('Error resetting notification count: $e');
      _showSnackBar('Error resetting notification count: $e', Colors.red);
    }
  }

  Future<void> _clearAllNotifications() async {
    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Clear All Notifications', style: GoogleFonts.poppins()),
        content: Text(
          'This will clear all notification data from your device. This action cannot be undone.',
          style: GoogleFonts.poppins(),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Cancel', style: GoogleFonts.poppins()),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: Text('Clear All', style: GoogleFonts.poppins()),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        await _notificationService.resetNotificationCount();
        _showSnackBar('All notifications cleared', Colors.green);
      } catch (e) {
        _logger.e('Error clearing notifications: $e');
        _showSnackBar('Error clearing notifications: $e', Colors.red);
      }
    }
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Notification Settings',
          style: GoogleFonts.poppins(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
        backgroundColor: Colors.blueGrey,
        iconTheme: const IconThemeData(color: Colors.white),
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
                    'Notification Preferences',
                    style: GoogleFonts.poppins(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: Colors.blueGrey[800],
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Configure how you receive maintenance notifications',
                    style: GoogleFonts.poppins(
                      color: Colors.grey[600],
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 24),

                  // General Settings Card
                  Card(
                    elevation: 4,
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.settings, color: Colors.blueGrey[700], size: 24),
                              const SizedBox(width: 12),
                              Text(
                                'General Settings',
                                style: GoogleFonts.poppins(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.blueGrey[800],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          
                          _buildSettingTile(
                            title: 'Enable Notifications',
                            subtitle: 'Receive maintenance task notifications',
                            value: _notificationsEnabled,
                            onChanged: _updateNotificationsEnabled,
                            icon: Icons.notifications,
                            iconColor: Colors.blue,
                          ),
                          
                          const Divider(),
                          
                          _buildSettingTile(
                            title: 'Automatic Notifications',
                            subtitle: 'Automatically schedule notifications for all tasks',
                            value: _autoNotificationsEnabled,
                            onChanged: _notificationsEnabled ? _updateAutoNotificationsEnabled : null,
                            icon: Icons.autorenew,
                            iconColor: Colors.green,
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 16),

                  // Device Settings Card
                  Card(
                    elevation: 4,
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.phone_android, color: Colors.blueGrey[700], size: 24),
                              const SizedBox(width: 12),
                              Text(
                                'Device Settings',
                                style: GoogleFonts.poppins(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.blueGrey[800],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          
                          _buildSettingTile(
                            title: 'Sound',
                            subtitle: 'Play sound when notifications arrive',
                            value: _soundEnabled,
                            onChanged: _notificationsEnabled ? _updateSoundEnabled : null,
                            icon: Icons.volume_up,
                            iconColor: Colors.orange,
                          ),
                          
                          const Divider(),
                          
                          _buildSettingTile(
                            title: 'Vibration',
                            subtitle: 'Vibrate device for notifications',
                            value: _vibrationEnabled,
                            onChanged: _notificationsEnabled ? _updateVibrationEnabled : null,
                            icon: Icons.vibration,
                            iconColor: Colors.purple,
                          ),
                          
                          const Divider(),
                          
                          _buildSettingTile(
                            title: 'Screen Wake',
                            subtitle: 'Wake screen for urgent notifications',
                            value: _screenWakeEnabled,
                            onChanged: _notificationsEnabled ? _updateScreenWakeEnabled : null,
                            icon: Icons.screen_lock_portrait,
                            iconColor: Colors.red,
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 16),

                  // Actions Card
                  Card(
                    elevation: 4,
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.build, color: Colors.blueGrey[700], size: 24),
                              const SizedBox(width: 12),
                              Text(
                                'Actions',
                                style: GoogleFonts.poppins(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.blueGrey[800],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          
                          ListTile(
                            leading: Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: Colors.blue[100],
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Icon(Icons.refresh, color: Colors.blue[700]),
                            ),
                            title: Text(
                              'Reset Notification Count',
                              style: GoogleFonts.poppins(fontWeight: FontWeight.w500),
                            ),
                            subtitle: Text(
                              'Clear the notification badge count',
                              style: GoogleFonts.poppins(fontSize: 12),
                            ),
                            trailing: ElevatedButton(
                              onPressed: _resetNotificationCount,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.blue,
                                foregroundColor: Colors.white,
                              ),
                              child: Text('Reset', style: GoogleFonts.poppins()),
                            ),
                          ),
                          
                          const Divider(),
                          
                          ListTile(
                            leading: Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: Colors.red[100],
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Icon(Icons.clear_all, color: Colors.red[700]),
                            ),
                            title: Text(
                              'Clear All Notifications',
                              style: GoogleFonts.poppins(fontWeight: FontWeight.w500),
                            ),
                            subtitle: Text(
                              'Remove all notification data from device',
                              style: GoogleFonts.poppins(fontSize: 12),
                            ),
                            trailing: ElevatedButton(
                              onPressed: _clearAllNotifications,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.red,
                                foregroundColor: Colors.white,
                              ),
                              child: Text('Clear', style: GoogleFonts.poppins()),
                            ),
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
                                  'About Notifications',
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
                            '• Notifications are sent at 9:00 AM, with a retry at 11:00 AM if needed\n'
                            '• Automatic notifications create a continuous cycle based on task frequencies\n'
                            '• Notifications work like WhatsApp - they appear on your status bar and wake your screen\n'
                            '• All users receive notifications, not just technicians\n'
                            '• Offline notifications will appear when you come back online',
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

  Widget _buildSettingTile({
    required String title,
    required String subtitle,
    required bool value,
    required Function(bool)? onChanged,
    required IconData icon,
    required Color iconColor,
  }) {
    return ListTile(
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: iconColor.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(icon, color: iconColor),
      ),
      title: Text(
        title,
        style: GoogleFonts.poppins(
          fontWeight: FontWeight.w500,
          color: onChanged != null ? Colors.black87 : Colors.grey,
        ),
      ),
      subtitle: Text(
        subtitle,
        style: GoogleFonts.poppins(
          fontSize: 12,
          color: onChanged != null ? Colors.grey[600] : Colors.grey[400],
        ),
      ),
      trailing: Switch(
        value: value,
        onChanged: onChanged,
        activeColor: iconColor,
      ),
    );
  }
}