import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:logger/logger.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cmms/models/notification_model.dart';
import 'package:cmms/models/task_status_model.dart';
import 'package:cmms/models/task_display_model.dart';
import 'package:cmms/services/task_display_service.dart';

class PreventiveMaintenanceScreen extends StatefulWidget {
  final String facilityId;

  const PreventiveMaintenanceScreen({super.key, required this.facilityId});

  @override
  State<PreventiveMaintenanceScreen> createState() => _PreventiveMaintenanceScreenState();
}

class _PreventiveMaintenanceScreenState extends State<PreventiveMaintenanceScreen> {
  final Logger _logger = Logger(printer: PrettyPrinter());
  final GlobalKey<ScaffoldMessengerState> _messengerKey = GlobalKey<ScaffoldMessengerState>();
  
  String _selectedTab = 'Tasks';
  String? _selectedCategory;
  
  final TaskDisplayService _taskDisplayService = TaskDisplayService();

  @override
  void initState() {
    super.initState();
    _logger.i('PreventiveMaintenanceScreen initialized: facilityId=${widget.facilityId}');
  }

  Future<void> _updateTaskStatus(TaskDisplayModel task, TaskStatus newStatus) async {
    try {
      if (!task.canUpdateStatus) {
        _showSnackBar('This task has no notification setup. Status cannot be updated.');
        return;
      }

      String? notes;
      
      // Show dialog for notes if marking as in progress or completed
      if (newStatus != TaskStatus.waiting) {
        notes = await _showNotesDialog(newStatus);
        if (notes == null) return; // User cancelled
      }

      await _taskDisplayService.updateTaskStatus(
        category: task.category,
        component: task.component,
        intervention: task.intervention,
        newStatus: newStatus,
        notes: notes,
      );

      _showSnackBar('Task status updated to ${newStatus.displayName}');
    } catch (e) {
      _logger.e('Error updating task status: $e');
      _showSnackBar('Error updating task status: $e');
    }
  }

  Future<String?> _showNotesDialog(TaskStatus status) async {
    final notesController = TextEditingController();
    
    return await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Update Task Status', style: GoogleFonts.poppins()),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Marking task as ${status.displayName}',
              style: GoogleFonts.poppins(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: notesController,
              decoration: InputDecoration(
                labelText: 'Notes (optional)',
                border: const OutlineInputBorder(),
                labelStyle: GoogleFonts.poppins(),
                hintText: 'Add any relevant notes...',
              ),
              style: GoogleFonts.poppins(),
              maxLines: 3,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, null),
            child: Text('Cancel', style: GoogleFonts.poppins()),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, notesController.text.trim()),
            style: ElevatedButton.styleFrom(
              backgroundColor: _getStatusColor(status),
              foregroundColor: Colors.white,
            ),
            child: Text('Update', style: GoogleFonts.poppins()),
          ),
        ],
      ),
    );
  }

  void _showTaskStatusMenu(TaskDisplayModel task) {
    if (!task.canUpdateStatus) {
      _showSnackBar('This task has no notification setup. Status cannot be updated.');
      return;
    }

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Container(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Update Task Status',
              style: GoogleFonts.poppins(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              task.component,
              style: GoogleFonts.poppins(
                fontSize: 14,
                color: Colors.grey[600],
              ),
            ),
            const SizedBox(height: 20),
            
            _buildStatusOption(task, TaskStatus.waiting),
            _buildStatusOption(task, TaskStatus.inProgress),
            _buildStatusOption(task, TaskStatus.completed),
            
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text('Cancel', style: GoogleFonts.poppins()),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusOption(TaskDisplayModel task, TaskStatus status) {
    final isSelected = task.status == status;
    
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: () {
          Navigator.pop(context);
          _updateTaskStatus(task, status);
        },
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: isSelected ? _getStatusColor(status).withValues(alpha: 0.1) : Colors.grey[50],
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: isSelected ? _getStatusColor(status) : Colors.grey[300]!,
              width: isSelected ? 2 : 1,
            ),
          ),
          child: Row(
            children: [
              Icon(
                _getStatusIcon(status),
                color: _getStatusColor(status),
                size: 24,
              ),
              const SizedBox(width: 12),
              Text(
                status.displayName,
                style: GoogleFonts.poppins(
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                  color: isSelected ? _getStatusColor(status) : Colors.black87,
                ),
              ),
              if (isSelected) ...[
                const Spacer(),
                Icon(
                  Icons.check_circle,
                  color: _getStatusColor(status),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Color _getStatusColor(TaskStatus status) {
    switch (status) {
      case TaskStatus.waiting:
        return Colors.grey;
      case TaskStatus.inProgress:
        return Colors.orange;
      case TaskStatus.completed:
        return Colors.green;
    }
  }

  IconData _getStatusIcon(TaskStatus status) {
    switch (status) {
      case TaskStatus.waiting:
        return Icons.schedule;
      case TaskStatus.inProgress:
        return Icons.play_circle;
      case TaskStatus.completed:
        return Icons.check_circle;
    }
  }

  void _showSnackBar(String message) {
    if (mounted) {
      _messengerKey.currentState?.showSnackBar(
        SnackBar(content: Text(message, style: GoogleFonts.poppins())),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return ScaffoldMessenger(
      key: _messengerKey,
      child: Scaffold(
        appBar: AppBar(
          title: Text('Maintenance Tasks', style: GoogleFonts.poppins(color: Colors.white, fontWeight: FontWeight.bold)),
          backgroundColor: Colors.blueGrey,
          iconTheme: const IconThemeData(color: Colors.white),
        ),
        body: SafeArea(
          child: Column(
            children: [
              // Tab Selection
              Container(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () => setState(() {
                          _selectedTab = 'Tasks';
                          _selectedCategory = null;
                        }),
                        icon: const Icon(Icons.assignment),
                        label: Text('Tasks', style: GoogleFonts.poppins()),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _selectedTab == 'Tasks' ? Colors.blueGrey : Colors.grey[300],
                          foregroundColor: _selectedTab == 'Tasks' ? Colors.white : Colors.black,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: StreamBuilder<QuerySnapshot>(
                        stream: FirebaseFirestore.instance
                            .collection('Notifications')
                            .snapshots(), // Removed the where clauses to show all notifications
                        builder: (context, snapshot) {
                          final notificationCount = snapshot.hasData ? snapshot.data!.docs.length : 0;
                          
                          return Stack(
                            children: [
                              SizedBox(
                                width: double.infinity,
                                child: ElevatedButton.icon(
                                  onPressed: () => setState(() {
                                    _selectedTab = 'Notifications';
                                    _selectedCategory = null;
                                  }),
                                  icon: const Icon(Icons.notifications),
                                  label: Text('Notifications', style: GoogleFonts.poppins()),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: _selectedTab == 'Notifications' ? Colors.blueGrey : Colors.grey[300],
                                    foregroundColor: _selectedTab == 'Notifications' ? Colors.white : Colors.black,
                                    padding: const EdgeInsets.symmetric(vertical: 12),
                                  ),
                                ),
                              ),
                              if (notificationCount > 0)
                                Positioned(
                                  right: 8,
                                  top: 4,
                                  child: Container(
                                    padding: const EdgeInsets.all(4),
                                    decoration: const BoxDecoration(
                                      color: Colors.red,
                                      shape: BoxShape.circle,
                                    ),
                                    child: Text(
                                      '$notificationCount',
                                      style: GoogleFonts.poppins(
                                        color: Colors.white,
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
              
              // Content
              Expanded(
                child: _selectedTab == 'Tasks' ? _buildTasksTab() : _buildNotificationsTab(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTasksTab() {
    if (_selectedCategory == null) {
      return _buildCategorySelection();
    } else {
      return _buildTasksList();
    }
  }

  Widget _buildCategorySelection() {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Select Category',
            style: GoogleFonts.poppins(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Colors.blueGrey[800],
            ),
          ),
          const SizedBox(height: 16),
          
          StreamBuilder<List<CategoryDisplayModel>>(
            stream: _taskDisplayService.getCategoriesWithTasks(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              
              if (snapshot.hasError) {
                return Center(
                  child: Text('Error: ${snapshot.error}', style: GoogleFonts.poppins()),
                );
              }
              
              final categories = snapshot.data ?? [];
              
              if (categories.isEmpty) {
                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.category, size: 64, color: Colors.grey[400]),
                      const SizedBox(height: 16),
                      Text(
                        'No categories found',
                        style: GoogleFonts.poppins(
                          fontSize: 18,
                          color: Colors.grey[600],
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Categories will appear here once maintenance tasks are set up',
                        style: GoogleFonts.poppins(color: Colors.grey[500]),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                );
              }
              
              return Expanded(
                child: ListView.builder(
                  itemCount: categories.length,
                  itemBuilder: (context, index) {
                    final category = categories[index];
                    return Card(
                      margin: const EdgeInsets.only(bottom: 12),
                      elevation: 3,
                      child: InkWell(
                        onTap: () => setState(() => _selectedCategory = category.category),
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
                                      color: _getStatusColor(category.overallStatus),
                                      borderRadius: BorderRadius.circular(20),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(
                                          _getStatusIcon(category.overallStatus),
                                          color: Colors.white,
                                          size: 16,
                                        ),
                                        const SizedBox(width: 4),
                                        Text(
                                          category.overallStatus.displayName,
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
                                  Icon(Icons.arrow_forward_ios, color: Colors.grey[400]),
                                ],
                              ),
                              const SizedBox(height: 12),
                              Text(
                                category.category,
                                style: GoogleFonts.poppins(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Wrap(
                                spacing: 8,
                                runSpacing: 4,
                                children: [
                                  _buildTaskCountChip('Total', category.totalTasks, Colors.blueGrey),
                                  _buildTaskCountChip('Waiting', category.waitingTasks, Colors.grey),
                                  _buildTaskCountChip('In Progress', category.inProgressTasks, Colors.orange),
                                  _buildTaskCountChip('Completed', category.completedTasks, Colors.green),
                                  if (category.noStatusTasks > 0)
                                    _buildTaskCountChip('No Status', category.noStatusTasks, Colors.red),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildTaskCountChip(String label, int count, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(
        '$label: $count',
        style: GoogleFonts.poppins(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  Widget _buildTasksList() {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              IconButton(
                onPressed: () => setState(() => _selectedCategory = null),
                icon: const Icon(Icons.arrow_back),
              ),
              Expanded(
                child: Text(
                  '$_selectedCategory Tasks',
                  style: GoogleFonts.poppins(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Colors.blueGrey[800],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          
          Expanded(
            child: StreamBuilder<List<CategoryDisplayModel>>(
              stream: _taskDisplayService.getCategoriesWithTasks(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                
                if (snapshot.hasError) {
                  return Center(
                    child: Text('Error: ${snapshot.error}', style: GoogleFonts.poppins()),
                  );
                }
                
                final categories = snapshot.data ?? [];
                final selectedCategoryData = categories.firstWhere(
                  (cat) => cat.category == _selectedCategory,
                  orElse: () => CategoryDisplayModel.fromTasks(_selectedCategory!, []),
                );
                
                final tasks = selectedCategoryData.tasks;
                
                if (tasks.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.assignment, size: 64, color: Colors.grey[400]),
                        const SizedBox(height: 16),
                        Text(
                          'No tasks found in this category',
                          style: GoogleFonts.poppins(
                            fontSize: 18,
                            color: Colors.grey[600],
                          ),
                        ),
                      ],
                    ),
                  );
                }
                
                return ListView.builder(
                  itemCount: tasks.length,
                  itemBuilder: (context, index) {
                    final task = tasks[index];
                    return Card(
                      margin: const EdgeInsets.only(bottom: 12),
                      elevation: 2,
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    task.component,
                                    style: GoogleFonts.poppins(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: task.hasNotification 
                                        ? _getStatusColor(task.status)
                                        : Colors.grey[400],
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Text(
                                    task.statusDisplay,
                                    style: GoogleFonts.poppins(
                                      color: Colors.white,
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Text(
                              task.intervention,
                              style: GoogleFonts.poppins(color: Colors.grey[700]),
                            ),
                            if (task.lastInspectionDate != null) ...[
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  Icon(Icons.history, size: 16, color: Colors.grey[600]),
                                  const SizedBox(width: 4),
                                  Text(
                                    'Last: ${DateFormat.yMMMd().format(task.lastInspectionDate!)}',
                                    style: GoogleFonts.poppins(
                                      fontSize: 12,
                                      color: Colors.grey[600],
                                    ),
                                  ),
                                  const SizedBox(width: 16),
                                  Icon(Icons.schedule, size: 16, color: Colors.grey[600]),
                                  const SizedBox(width: 4),
                                  Text(
                                    'Next: ${DateFormat.yMMMd().format(task.nextInspectionDate!)}',
                                    style: GoogleFonts.poppins(
                                      fontSize: 12,
                                      color: Colors.grey[600],
                                    ),
                                  ),
                                ],
                              ),
                            ],
                            if (task.notes != null && task.notes!.isNotEmpty) ...[
                              const SizedBox(height: 8),
                              Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: Colors.grey[100],
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Row(
                                  children: [
                                    Icon(Icons.note, size: 16, color: Colors.grey[600]),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        task.notes!,
                                        style: GoogleFonts.poppins(
                                          fontSize: 12,
                                          color: Colors.grey[700],
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                Expanded(
                                  child: ElevatedButton.icon(
                                    onPressed: task.canUpdateStatus
                                        ? () => _showTaskStatusMenu(task)
                                        : null,
                                    icon: const Icon(Icons.edit, size: 16),
                                    label: Text(
                                      task.canUpdateStatus ? 'Update Status' : 'No Notification',
                                      style: GoogleFonts.poppins(fontSize: 12),
                                    ),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: task.canUpdateStatus ? Colors.blueGrey : Colors.grey[400],
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
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNotificationsTab() {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Maintenance Notifications',
            style: GoogleFonts.poppins(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Colors.blueGrey[800],
            ),
          ),
          const SizedBox(height: 16),
          
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('Notifications')
                  .orderBy('notificationDate', descending: true)
                  .snapshots(), // Removed the where clauses
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                
                if (snapshot.hasError) {
                  return Center(
                    child: Text('Error: ${snapshot.error}', style: GoogleFonts.poppins()),
                  );
                }
                
                final notifications = snapshot.data?.docs ?? [];
                
                if (notifications.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.notifications_none, size: 64, color: Colors.grey[400]),
                        const SizedBox(height: 16),
                        Text(
                          'No notifications found',
                          style: GoogleFonts.poppins(
                            fontSize: 18,
                            color: Colors.grey[600],
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Maintenance notifications will appear here',
                          style: GoogleFonts.poppins(color: Colors.grey[500]),
                        ),
                      ],
                    ),
                  );
                }
                
                return ListView.builder(
                  itemCount: notifications.length,
                  itemBuilder: (context, index) {
                    final doc = notifications[index];
                    final notification = GroupedNotificationModel.fromFirestore(doc);
                    
                    return Card(
                      margin: const EdgeInsets.only(bottom: 12),
                      elevation: 3,
                      child: ExpansionTile(
                        leading: CircleAvatar(
                          backgroundColor: notification.isTriggered ? Colors.green : Colors.orange,
                          child: notification.isTriggered 
                              ? const Icon(Icons.check, color: Colors.white)
                              : Text(
                                  '${notification.notifications.length}',
                                  style: GoogleFonts.poppins(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                        ),
                        title: Text(
                          '${notification.isTriggered ? "Sent" : "Scheduled"}: ${DateFormat.yMMMd().format(notification.notificationDate)}',
                          style: GoogleFonts.poppins(fontWeight: FontWeight.bold),
                        ),
                        subtitle: Text(
                          '${notification.notifications.length} tasks in ${notification.notifications.map((n) => n.category).toSet().length} categories',
                          style: GoogleFonts.poppins(),
                        ),
                        children: notification.notifications.map((task) {
                          return ListTile(
                            contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
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
                                ),
                              ),
                            ),
                            title: Text(
                              task.component,
                              style: GoogleFonts.poppins(fontWeight: FontWeight.w500),
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
                                Text(
                                  'Last Inspection: ${DateFormat.yMMMd().format(task.lastInspectionDate)}',
                                  style: GoogleFonts.poppins(
                                    fontSize: 11,
                                    color: Colors.grey[600],
                                  ),
                                ),
                                Text(
                                  'Next Inspection: ${DateFormat.yMMMd().format(task.nextInspectionDate)}',
                                  style: GoogleFonts.poppins(
                                    fontSize: 11,
                                    color: Colors.grey[600],
                                  ),
                                ),
                              ],
                            ),
                            trailing: Text(
                              '${task.frequency}m',
                              style: GoogleFonts.poppins(
                                color: Colors.grey[600],
                                fontSize: 12,
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}