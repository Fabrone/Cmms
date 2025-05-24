import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:logger/logger.dart';
import 'package:cmms/models/maintenance_task_model.dart';
import 'package:cmms/services/notification_service.dart';

class NotificationSetupScreen extends StatefulWidget {
  final MaintenanceTaskModel task;
  final String taskId;

  const NotificationSetupScreen({
    super.key,
    required this.task,
    required this.taskId,
  });

  @override
  NotificationSetupScreenState createState() => NotificationSetupScreenState();
}

class NotificationSetupScreenState extends State<NotificationSetupScreen> {
  final logger = Logger(printer: PrettyPrinter());
  final GlobalKey<ScaffoldMessengerState> _messengerKey = GlobalKey<ScaffoldMessengerState>();
  
  DateTime? _lastInspectionDate;
  DateTime? _nextInspectionDate;
  DateTime? _notificationDate;
  
  final NotificationService _notificationService = NotificationService();
  
  @override
  void initState() {
    super.initState();
    _notificationService.initialize();
  }
  
  void _selectLastInspectionDate() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now().subtract(const Duration(days: 30)), // Default to 30 days ago
      firstDate: DateTime(2020), // Allow dates from 2020
      lastDate: DateTime.now(), // Don't allow future dates for last inspection
      helpText: 'Select Last Inspection Date',
      cancelText: 'Cancel',
      confirmText: 'Select',
    );
    
    if (picked != null) {
      setState(() {
        _lastInspectionDate = picked;
        _calculateDates();
      });
    }
  }
  
  void _calculateDates() {
    if (_lastInspectionDate != null) {
      final dates = _notificationService.calculateNotificationDates(
        lastInspectionDate: _lastInspectionDate!,
        frequencyMonths: widget.task.frequency,
      );
      
      setState(() {
        _nextInspectionDate = dates['nextInspectionDate'];
        _notificationDate = dates['notificationDate'];
      });
    }
  }
  
  Future<void> _setupNotification() async {
    if (_lastInspectionDate == null) {
      _showSnackBar('Please select the last inspection date first');
      return;
    }
    
    try {
      // Get all technician IDs
      final technicianIds = await _notificationService.getTechnicianIds();
      
      if (technicianIds.isEmpty) {
        _showSnackBar('No technicians found in the system');
        return;
      }
      
      // Create the notification
      final notificationId = await _notificationService.createNotification(
        task: widget.task,
        taskId: widget.taskId,
        lastInspectionDate: _lastInspectionDate!,
        assignedTechnicians: technicianIds,
      );
      
      _showSnackBar('Notification scheduled successfully!');
      logger.i('Notification created with ID: $notificationId');
      
      if (mounted) {
        Navigator.pop(context, true); // Return true to indicate success
      }
      
    } catch (e) {
      logger.e('Error setting up notification: $e');
      _showSnackBar('Error setting up notification: $e');
    }
  }
  
  void _showSnackBar(String message) {
    if (mounted) {
      _messengerKey.currentState?.showSnackBar(
        SnackBar(content: Text(message, style: GoogleFonts.poppins())),
      );
    }
  }
  
  String _formatDate(DateTime? date) {
    if (date == null) return 'Not set';
    return '${date.day}/${date.month}/${date.year}';
  }
  
  @override
  Widget build(BuildContext context) {
    return ScaffoldMessenger(
      key: _messengerKey,
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            'Setup Notification',
            style: GoogleFonts.poppins(color: Colors.white, fontWeight: FontWeight.bold),
          ),
          backgroundColor: Colors.blueGrey,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.white),
            onPressed: () => Navigator.pop(context),
          ),
        ),
        body: Padding(
          padding: const EdgeInsets.all(16.0),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Task Information Card
                Card(
                  elevation: 4,
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Task Information',
                          style: GoogleFonts.poppins(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Colors.blueGrey[800],
                          ),
                        ),
                        const SizedBox(height: 12),
                        _buildInfoRow('Category:', widget.task.category),
                        _buildInfoRow('Component:', widget.task.component),
                        _buildInfoRow('Frequency:', '${widget.task.frequency} months'),
                        const SizedBox(height: 8),
                        Text(
                          'Intervention:',
                          style: GoogleFonts.poppins(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          widget.task.intervention,
                          style: GoogleFonts.poppins(),
                        ),
                      ],
                    ),
                  ),
                ),
                
                const SizedBox(height: 20),
                
                // Date Selection Section
                Card(
                  elevation: 4,
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Inspection Schedule',
                          style: GoogleFonts.poppins(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Colors.blueGrey[800],
                          ),
                        ),
                        const SizedBox(height: 16),
                        
                        // Last Inspection Date
                        Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Last Inspection Date:',
                                    style: GoogleFonts.poppins(fontWeight: FontWeight.bold),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    _formatDate(_lastInspectionDate),
                                    style: GoogleFonts.poppins(
                                      color: _lastInspectionDate != null ? Colors.green[700] : Colors.red[700],
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            ElevatedButton.icon(
                              onPressed: _selectLastInspectionDate,
                              icon: const Icon(Icons.calendar_today),
                              label: Text('Select Date', style: GoogleFonts.poppins()),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.blueGrey,
                                foregroundColor: Colors.white,
                              ),
                            ),
                          ],
                        ),
                        
                        const SizedBox(height: 20),
                        
                        // Calculated Dates
                        if (_lastInspectionDate != null) ...[
                          const Divider(),
                          const SizedBox(height: 16),
                          Text(
                            'Calculated Schedule',
                            style: GoogleFonts.poppins(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Colors.blueGrey[700],
                            ),
                          ),
                          const SizedBox(height: 12),
                          
                          _buildCalculatedDateRow(
                            'Next Inspection Date:',
                            _nextInspectionDate,
                            Icons.event,
                            Colors.blue,
                          ),
                          
                          const SizedBox(height: 8),
                          
                          _buildCalculatedDateRow(
                            'Notification Date:',
                            _notificationDate,
                            Icons.notifications,
                            Colors.orange,
                          ),
                          
                          const SizedBox(height: 16),
                          
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.blue[50],
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.blue[200]!),
                            ),
                            child: Row(
                              children: [
                                Icon(Icons.info, color: Colors.blue[700]),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    'Technicians will be notified 5 days before the next inspection is due.',
                                    style: GoogleFonts.poppins(
                                      color: Colors.blue[700],
                                      fontSize: 13,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                
                const SizedBox(height: 30),
                
                // Action Buttons
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: Text('Cancel', style: GoogleFonts.poppins()),
                    ),
                    const SizedBox(width: 12),
                    ElevatedButton.icon(
                      onPressed: _lastInspectionDate != null ? _setupNotification : null,
                      icon: const Icon(Icons.notifications_active),
                      label: Text('Setup Notification', style: GoogleFonts.poppins()),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
  
  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: GoogleFonts.poppins(fontWeight: FontWeight.bold),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: GoogleFonts.poppins(),
            ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildCalculatedDateRow(String label, DateTime? date, IconData icon, Color color) {
    return Row(
      children: [
        Icon(icon, color: color, size: 20),
        const SizedBox(width: 8),
        Text(
          label,
          style: GoogleFonts.poppins(fontWeight: FontWeight.w500),
        ),
        const Spacer(),
        Text(
          _formatDate(date),
          style: GoogleFonts.poppins(
            color: color,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }
}
