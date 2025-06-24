import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:logger/logger.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cmms/notifications/models/maintenance_task_model.dart';
import 'package:cmms/notifications/services/notification_service.dart';
import 'package:cmms/notifications/screens/notification_setup_tracking_screen.dart';

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
  
  List<CategoryTaskGroup> _categoryGroups = [];
  bool _isLoading = true;
  
  @override
  void initState() {
    super.initState();
    _notificationService.initialize();
    _loadCategoryGroups();
  }
  
  Future<void> _loadCategoryGroups() async {
    try {
      setState(() {
        _isLoading = true;
      });
      
      final tasksSnapshot = await _firestore
          .collection('Maintenance_Tasks')
          .orderBy('category')
          .get();
      
      // Group tasks by category and frequency
      final Map<String, Map<int, List<MaintenanceTaskModel>>> groupedTasks = {};
      
      for (var doc in tasksSnapshot.docs) {
        final task = MaintenanceTaskModel.fromFirestore(doc);
        
        if (!groupedTasks.containsKey(task.category)) {
          groupedTasks[task.category] = {};
        }
        
        if (!groupedTasks[task.category]!.containsKey(task.frequency)) {
          groupedTasks[task.category]![task.frequency] = [];
        }
        
        groupedTasks[task.category]![task.frequency]!.add(task);
      }
      
      // Create category groups with frequency subgroups
      final categoryGroups = <CategoryTaskGroup>[];
      groupedTasks.forEach((category, frequencyMap) {
        final frequencyGroups = <FrequencyTaskGroup>[];
        
        frequencyMap.forEach((frequency, tasks) {
          frequencyGroups.add(FrequencyTaskGroup(
            frequency: frequency,
            tasks: tasks,
          ));
        });
        
        // Sort frequency groups by frequency
        frequencyGroups.sort((a, b) => a.frequency.compareTo(b.frequency));
        
        categoryGroups.add(CategoryTaskGroup(
          category: category,
          frequencyGroups: frequencyGroups,
        ));
      });
      
      setState(() {
        _categoryGroups = categoryGroups;
        _isLoading = false;
      });
      
    } catch (e) {
      logger.e('Error loading category groups: $e');
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
      final selectedTasks = _getSelectedTasks();
      
      if (selectedTasks.isNotEmpty) {
        // Use the shortest frequency among selected tasks for notification timing
        final shortestFrequency = selectedTasks
            .map((t) => t.frequency)
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
  
  List<MaintenanceTaskModel> _getSelectedTasks() {
    final List<MaintenanceTaskModel> selectedTasks = [];
    
    for (final categoryGroup in _categoryGroups) {
      for (final frequencyGroup in categoryGroup.frequencyGroups) {
        if (frequencyGroup.isSelected == true) {
          selectedTasks.addAll(frequencyGroup.tasks);
        } else {
          // Check individual task selections
          for (final task in frequencyGroup.tasks) {
            if (frequencyGroup.selectedTasks.contains(task)) {
              selectedTasks.add(task);
            }
          }
        }
      }
    }
    
    return selectedTasks;
  }
  
  void _toggleCategorySelection(CategoryTaskGroup categoryGroup, bool? value) {
    setState(() {
      for (final frequencyGroup in categoryGroup.frequencyGroups) {
        frequencyGroup.isSelected = value ?? false;
        if (value == true) {
          frequencyGroup.selectedTasks.clear();
          frequencyGroup.selectedTasks.addAll(frequencyGroup.tasks);
        } else {
          frequencyGroup.selectedTasks.clear();
        }
      }
      _calculateDates();
    });
  }
  
  void _toggleFrequencyGroupSelection(FrequencyTaskGroup frequencyGroup, bool? value) {
    setState(() {
      frequencyGroup.isSelected = value ?? false;
      if (value == true) {
        frequencyGroup.selectedTasks.clear();
        frequencyGroup.selectedTasks.addAll(frequencyGroup.tasks);
      } else {
        frequencyGroup.selectedTasks.clear();
      }
      _calculateDates();
    });
  }
  
  void _toggleTaskSelection(FrequencyTaskGroup frequencyGroup, MaintenanceTaskModel task, bool? value) {
    setState(() {
      if (value == true) {
        frequencyGroup.selectedTasks.add(task);
      } else {
        frequencyGroup.selectedTasks.remove(task);
      }
      
      // Update frequency group selection state
      if (frequencyGroup.selectedTasks.length == frequencyGroup.tasks.length) {
        frequencyGroup.isSelected = true;
      } else if (frequencyGroup.selectedTasks.isEmpty) {
        frequencyGroup.isSelected = false;
      } else {
        frequencyGroup.isSelected = null; // Indeterminate state
      }
      
      _calculateDates();
    });
  }
  
  bool _isCategoryFullySelected(CategoryTaskGroup categoryGroup) {
    return categoryGroup.frequencyGroups.every((fg) => fg.isSelected == true);
  }
  
  bool _isCategoryPartiallySelected(CategoryTaskGroup categoryGroup) {
    return categoryGroup.frequencyGroups.any((fg) => 
        fg.isSelected == true || fg.selectedTasks.isNotEmpty);
  }
  
  Future<void> _setupNotification() async {
    final selectedTasks = _getSelectedTasks();
    
    if (selectedTasks.isEmpty) {
      _showSnackBar('Please select at least one task');
      return;
    }
    
    if (_lastInspectionDate == null) {
      _showSnackBar('Please select the last inspection date first');
      return;
    }
    
    try {
      // Get all user IDs (not just technicians)
      final userIds = await _notificationService.getAllUserIds();
      
      if (userIds.isEmpty) {
        _showSnackBar('No users found in the system');
        return;
      }
      
      // Create frequency-based notifications
      final notificationId = await _notificationService.createFrequencyBasedNotification(
        tasks: selectedTasks,
        lastInspectionDate: _lastInspectionDate!,
        assignedUsers: userIds,
      );
      
      _showSnackBar('Notification scheduled successfully for ${selectedTasks.length} tasks!');
      logger.i('Frequency-based notification created with ID: $notificationId');
      
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
            'Setup Custom Notification',
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
                      // Task Selection Card
                      Card(
                        elevation: 4,
                        child: Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Select Tasks for Notification',
                                style: GoogleFonts.poppins(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.blueGrey[800],
                                ),
                              ),
                              const SizedBox(height: 12),
                              Text(
                                'Tasks are grouped by category and frequency. Select individual tasks or entire groups:',
                                style: GoogleFonts.poppins(
                                  color: Colors.grey[600],
                                  fontSize: 14,
                                ),
                              ),
                              const SizedBox(height: 16),
                              
                              if (_categoryGroups.isEmpty)
                                Center(
                                  child: Text(
                                    'No categories found. Please add some maintenance tasks first.',
                                    style: GoogleFonts.poppins(color: Colors.grey[600]),
                                  ),
                                )
                              else
                                ...(_categoryGroups.map((categoryGroup) => Card(
                                  margin: const EdgeInsets.only(bottom: 8),
                                  elevation: 1,
                                  child: Theme(
                                    data: Theme.of(context).copyWith(
                                      dividerColor: Colors.transparent,
                                    ),
                                    child: ExpansionTile(
                                      leading: Checkbox(
                                        value: _isCategoryFullySelected(categoryGroup) 
                                            ? true 
                                            : _isCategoryPartiallySelected(categoryGroup) 
                                                ? null 
                                                : false,
                                        tristate: true,
                                        onChanged: (value) => _toggleCategorySelection(categoryGroup, value),
                                      ),
                                      title: Text(
                                        categoryGroup.category,
                                        style: GoogleFonts.poppins(fontWeight: FontWeight.bold),
                                      ),
                                      subtitle: Text(
                                        '${categoryGroup.frequencyGroups.length} frequency groups, ${categoryGroup.getTotalTasks()} total tasks',
                                        style: GoogleFonts.poppins(fontSize: 12),
                                      ),
                                      children: [
                                        Padding(
                                          padding: const EdgeInsets.symmetric(horizontal: 16.0),
                                          child: Column(
                                            children: categoryGroup.frequencyGroups.map((frequencyGroup) {
                                              return Card(
                                                margin: const EdgeInsets.only(bottom: 8),
                                                color: Colors.grey[50],
                                                child: Theme(
                                                  data: Theme.of(context).copyWith(
                                                    dividerColor: Colors.transparent,
                                                  ),
                                                  child: ExpansionTile(
                                                    leading: Checkbox(
                                                      value: frequencyGroup.isSelected,
                                                      tristate: true,
                                                      onChanged: (value) => _toggleFrequencyGroupSelection(frequencyGroup, value),
                                                    ),
                                                    title: Row(
                                                      children: [
                                                        Container(
                                                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                                          decoration: BoxDecoration(
                                                            color: Colors.blueGrey[100],
                                                            borderRadius: BorderRadius.circular(12),
                                                          ),
                                                          child: Text(
                                                            '${frequencyGroup.frequency} months',
                                                            style: GoogleFonts.poppins(
                                                              fontSize: 12,
                                                              fontWeight: FontWeight.bold,
                                                              color: Colors.blueGrey[700],
                                                            ),
                                                          ),
                                                        ),
                                                        const SizedBox(width: 8),
                                                        Text(
                                                          '${frequencyGroup.tasks.length} tasks',
                                                          style: GoogleFonts.poppins(fontSize: 14),
                                                        ),
                                                      ],
                                                    ),
                                                    children: [
                                                      Padding(
                                                        padding: const EdgeInsets.symmetric(horizontal: 16.0),
                                                        child: Column(
                                                          children: frequencyGroup.tasks.map((task) {
                                                            final isSelected = frequencyGroup.selectedTasks.contains(task);
                                                            return CheckboxListTile(
                                                              value: isSelected,
                                                              onChanged: (value) => _toggleTaskSelection(frequencyGroup, task, value),
                                                              title: Text(
                                                                task.component,
                                                                style: GoogleFonts.poppins(
                                                                  fontSize: 13,
                                                                  fontWeight: FontWeight.w500,
                                                                ),
                                                              ),
                                                              subtitle: Text(
                                                                task.intervention,
                                                                style: GoogleFonts.poppins(
                                                                  fontSize: 11,
                                                                  color: Colors.grey[600],
                                                                ),
                                                                maxLines: 2,
                                                                overflow: TextOverflow.ellipsis,
                                                              ),
                                                              controlAffinity: ListTileControlAffinity.leading,
                                                              dense: true,
                                                            );
                                                          }).toList(),
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                              );
                                            }).toList(),
                                          ),
                                        ),
                                      ],
                                    ),
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
                              if (_lastInspectionDate != null && _getSelectedTasks().isNotEmpty) ...[
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
                                              'Selected Tasks: ${_getSelectedTasks().length}',
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
                                        'All users will be notified at 9:00 AM, 5 days before the next inspection is due. Tasks with the same notification date will be grouped together.',
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
                            onPressed: (_lastInspectionDate != null && _getSelectedTasks().isNotEmpty) 
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

// Helper classes for organizing tasks
class CategoryTaskGroup {
  final String category;
  final List<FrequencyTaskGroup> frequencyGroups;

  CategoryTaskGroup({
    required this.category,
    required this.frequencyGroups,
  });

  int getTotalTasks() {
    return frequencyGroups.fold(0, (total, group) => total + group.tasks.length);
  }
}

class FrequencyTaskGroup {
  final int frequency;
  final List<MaintenanceTaskModel> tasks;
  final List<MaintenanceTaskModel> selectedTasks = [];
  bool? isSelected = false; // null for indeterminate state

  FrequencyTaskGroup({
    required this.frequency,
    required this.tasks,
  });
}
