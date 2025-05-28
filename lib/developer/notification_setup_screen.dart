import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:logger/logger.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cmms/models/maintenance_task_model.dart';
import 'package:cmms/services/notification_service.dart';
import 'package:cmms/screens/notification_setup_tracking_screen.dart';

class CategoryInfo {
  final String category;
  final int frequency;
  final List<MaintenanceTaskModel> tasks;
  bool isSelected;

  CategoryInfo({
    required this.category,
    required this.frequency,
    required this.tasks,
    this.isSelected = false,
  });
}

class NotificationSetupScreen extends StatefulWidget {
  const NotificationSetupScreen({super.key});

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
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  
  List<CategoryInfo> _categories = [];
  bool _isLoading = true;
  
  @override
  void initState() {
    super.initState();
    _notificationService.initialize();
    _loadCategories();
  }
  
  Future<void> _loadCategories() async {
    try {
      setState(() {
        _isLoading = true;
      });
      
      final tasksSnapshot = await _firestore
          .collection('Maintenance_Tasks')
          .orderBy('category')
          .get();
      
      // Group tasks by category
      final Map<String, List<MaintenanceTaskModel>> groupedTasks = {};
      
      for (var doc in tasksSnapshot.docs) {
        final task = MaintenanceTaskModel.fromFirestore(doc);
        if (!groupedTasks.containsKey(task.category)) {
          groupedTasks[task.category] = [];
        }
        groupedTasks[task.category]!.add(task);
      }
      
      // Create category info list
      final categories = <CategoryInfo>[];
      groupedTasks.forEach((category, tasks) {
        // Use the most common frequency for the category
        final frequencies = tasks.map((t) => t.frequency).toList();
        final frequency = frequencies.isNotEmpty ? frequencies.first : 0;
        
        categories.add(CategoryInfo(
          category: category,
          frequency: frequency,
          tasks: tasks,
        ));
      });
      
      setState(() {
        _categories = categories;
        _isLoading = false;
      });
      
    } catch (e) {
      logger.e('Error loading categories: $e');
      setState(() {
        _isLoading = false;
      });
      _showSnackBar('Error loading categories: $e');
    }
  }
  
  void _selectLastInspectionDate() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now().subtract(const Duration(days: 30)),
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
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
      final selectedCategories = _categories.where((c) => c.isSelected).toList();
      
      if (selectedCategories.isNotEmpty) {
        // Use the shortest frequency among selected categories for notification timing
        final shortestFrequency = selectedCategories
            .map((c) => c.frequency)
            .reduce((a, b) => a < b ? a : b);
        
        final dates = _notificationService.calculateNotificationDates(
          lastInspectionDate: _lastInspectionDate!,
          frequencyMonths: shortestFrequency,
        );
        
        setState(() {
          _nextInspectionDate = dates['nextInspectionDate'];
          _notificationDate = dates['notificationDate'];
        });
      }
    }
  }
  
  Future<void> _setupNotification() async {
    final selectedCategories = _categories.where((c) => c.isSelected).toList();
    
    if (selectedCategories.isEmpty) {
      _showSnackBar('Please select at least one category');
      return;
    }
    
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
      
      // Create notifications for all selected categories as a group
      final notificationId = await _notificationService.createGroupedNotification(
        categories: selectedCategories,
        lastInspectionDate: _lastInspectionDate!,
        assignedTechnicians: technicianIds,
      );
      
      _showSnackBar('Notification scheduled successfully for ${selectedCategories.length} categories!');
      logger.i('Grouped notification created with ID: $notificationId');
      
      if (mounted) {
        Navigator.pop(context, true);
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
          actions: [
            IconButton(
              icon: const Icon(Icons.track_changes, color: Colors.white),
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const NotificationSetupTrackingScreen(),
                  ),
                );
              },
              tooltip: 'Track Notifications',
            ),
          ],
        ),
        body: Padding(
          padding: const EdgeInsets.all(16.0),
          child: _isLoading 
              ? const Center(child: CircularProgressIndicator())
              : SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Categories Selection Card
                      Card(
                        elevation: 4,
                        child: Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Select Categories for Notification',
                                style: GoogleFonts.poppins(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.blueGrey[800],
                                ),
                              ),
                              const SizedBox(height: 12),
                              Text(
                                'Choose one or more categories to group in a single notification:',
                                style: GoogleFonts.poppins(
                                  color: Colors.grey[600],
                                  fontSize: 14,
                                ),
                              ),
                              const SizedBox(height: 16),
                              
                              if (_categories.isEmpty)
                                Center(
                                  child: Text(
                                    'No categories found. Please add some maintenance tasks first.',
                                    style: GoogleFonts.poppins(color: Colors.grey[600]),
                                  ),
                                )
                              else
                                ...(_categories.map((categoryInfo) => Card(
                                  margin: const EdgeInsets.only(bottom: 8),
                                  elevation: 1,
                                  child: CheckboxListTile(
                                    value: categoryInfo.isSelected,
                                    onChanged: (bool? value) {
                                      setState(() {
                                        categoryInfo.isSelected = value ?? false;
                                        _calculateDates();
                                      });
                                    },
                                    title: Text(
                                      categoryInfo.category,
                                      style: GoogleFonts.poppins(fontWeight: FontWeight.bold),
                                    ),
                                    subtitle: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'Frequency: ${categoryInfo.frequency} months',
                                          style: GoogleFonts.poppins(fontSize: 12),
                                        ),
                                        Text(
                                          '${categoryInfo.tasks.length} task(s) in this category',
                                          style: GoogleFonts.poppins(
                                            fontSize: 11,
                                            color: Colors.grey[600],
                                          ),
                                        ),
                                      ],
                                    ),
                                    secondary: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: Colors.blueGrey[100],
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: Text(
                                        '${categoryInfo.frequency}m',
                                        style: GoogleFonts.poppins(
                                          fontSize: 12,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                    controlAffinity: ListTileControlAffinity.leading,
                                  ),
                                ))),
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
                              if (_lastInspectionDate != null && _categories.any((c) => c.isSelected)) ...[
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
                                  child: Column(
                                    children: [
                                      Row(
                                        children: [
                                          Icon(Icons.info, color: Colors.blue[700]),
                                          const SizedBox(width: 8),
                                          Expanded(
                                            child: Text(
                                              'Selected Categories: ${_categories.where((c) => c.isSelected).map((c) => c.category).join(', ')}',
                                              style: GoogleFonts.poppins(
                                                color: Colors.blue[700],
                                                fontSize: 13,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 8),
                                      Text(
                                        'Technicians will be notified at 9:00 AM, 5 days before the next inspection is due. All selected categories will be grouped in one notification.',
                                        style: GoogleFonts.poppins(
                                          color: Colors.blue[700],
                                          fontSize: 13,
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
                            onPressed: (_lastInspectionDate != null && _categories.any((c) => c.isSelected)) 
                                ? _setupNotification 
                                : null,
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
