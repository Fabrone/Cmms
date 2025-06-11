import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:logger/logger.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cmms/models/notification_model.dart';
import 'package:cmms/models/task_status_model.dart';
import 'package:cmms/models/task_display_model.dart';
import 'package:cmms/services/task_display_service.dart';
import 'package:cmms/services/notification_service.dart';
import 'package:cmms/screens/notification_details_screen.dart';
import 'package:cmms/widgets/responsive_screen_wrapper.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class PreventiveMaintenanceScreen extends StatefulWidget {
  final String facilityId;

  const PreventiveMaintenanceScreen({super.key, required this.facilityId});

  @override
  State<PreventiveMaintenanceScreen> createState() => _PreventiveMaintenanceScreenState();
}

class _PreventiveMaintenanceScreenState extends State<PreventiveMaintenanceScreen> {
  final Logger _logger = Logger(printer: PrettyPrinter());
  
  String _selectedTab = 'Tasks';
  String? _selectedCategory;
  String _currentRole = 'User';
  String _organization = '-';
  
  final TaskDisplayService _taskDisplayService = TaskDisplayService();
  final NotificationService _notificationService = NotificationService();

  @override
  void initState() {
    super.initState();
    _logger.i('PreventiveMaintenanceScreen initialized: facilityId=${widget.facilityId}');
    _notificationService.initialize();
    _getCurrentUserRole();
  }

  Future<void> _getCurrentUserRole() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      final adminDoc = await FirebaseFirestore.instance.collection('Admins').doc(user.uid).get();
      final developerDoc = await FirebaseFirestore.instance.collection('Developers').doc(user.uid).get();
      final technicianDoc = await FirebaseFirestore.instance.collection('Technicians').doc(user.uid).get();
      final userDoc = await FirebaseFirestore.instance.collection('Users').doc(user.uid).get();
      
      String newRole = 'User';
      String newOrg = '-';
      
      if (adminDoc.exists) {
        newRole = 'Admin';
        final adminData = adminDoc.data();
        newOrg = adminData?['organization'] ?? '-';
      } 
      else if (developerDoc.exists) {
        newRole = 'Technician';
        newOrg = 'JV Almacis';
      }
      else if (technicianDoc.exists) {
        newRole = 'Technician';
        final techData = technicianDoc.data();
        newOrg = techData?['organization'] ?? '-';
      }
      else if (userDoc.exists) {
        final userData = userDoc.data();
        if (userData != null && userData['role'] == 'Technician') {
          newRole = 'Technician';
          newOrg = '-';
        } else {
          newRole = 'User';
          newOrg = '-';
        }
      }
      
      if (mounted) {
        setState(() {
          _currentRole = newRole;
          _organization = newOrg;
        });
      }
    } catch (e) {
      _logger.e('Error getting user role: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return ResponsiveScreenWrapper(
      title: 'Maintenance Tasks',
      facilityId: widget.facilityId,
      currentRole: _currentRole,
      organization: _organization,
      child: _buildBody(),
    );
  }

  Widget _buildBody() {
    return Column(
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
                child: StreamBuilder<int>(
                  stream: _notificationService.getNotificationCountStream(),
                  builder: (context, snapshot) {
                    final notificationCount = snapshot.data ?? 0;
                    
                    return Stack(
                      children: [
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            onPressed: () => setState(() {
                              _selectedTab = 'Notifications';
                              _selectedCategory = null;
                              _notificationService.resetNotificationCount();
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
    );
  }

  // Rest of the methods remain the same as in the original file...
  // (All the task management, notification handling, and UI building methods)
  
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
                                  _buildTaskCountChip('In Progress', category.inProgressTasks, Colors.blueGrey[700]!),
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
            child: StreamBuilder<List<GroupedNotificationModel>>(
              stream: _notificationService.getAllNotifications(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                
                if (snapshot.hasError) {
                  return Center(
                    child: Text('Error: ${snapshot.error}', style: GoogleFonts.poppins()),
                  );
                }
                
                final notifications = snapshot.data ?? [];
                
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
                          'Scheduled and received maintenance notifications will appear here',
                          style: GoogleFonts.poppins(color: Colors.grey[500]),
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
    );
  }

  // Helper methods for task management and UI components
  Future<void> _updateTaskStatus(TaskDisplayModel task, TaskStatus newStatus) async {
    try {
      if (!task.canUpdateStatus) {
        _showSnackBar('This task has no notification setup. Status cannot be updated.');
        return;
      }

      String? notes;
      
      if (newStatus != TaskStatus.waiting) {
        notes = await _showNotesDialog(newStatus);
        if (notes == null) return;
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

  Widget _buildNotificationCard(GroupedNotificationModel notification) {
    final categories = notification.notifications.map((n) => n.category).toSet().toList();
    
    final now = DateTime.now();
    final isOverdue = notification.notificationDate.isBefore(now) && !notification.isTriggered;
    final isDueToday = DateFormat.yMd().format(notification.notificationDate) == 
                      DateFormat.yMd().format(now);
    
    Color statusColor;
    String statusText;
    IconData statusIcon;
    
    if (notification.isTriggered) {
      statusColor = Colors.green;
      statusText = 'Received';
      statusIcon = Icons.check_circle;
    } else if (isOverdue) {
      statusColor = Colors.red;
      statusText = 'Overdue';
      statusIcon = Icons.error;
    } else if (isDueToday) {
      statusColor = Colors.blueGrey[700]!;
      statusText = 'Due Today';
      statusIcon = Icons.schedule;
    } else {
      statusColor = Colors.blueGrey;
      statusText = 'Scheduled';
      statusIcon = Icons.schedule_send;
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 3,
      child: InkWell(
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => NotificationDetailsScreen(notifications: [notification]),
            ),
          );
        },
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
            ],
          ),
        ),
      ),
    );
  }

  Color _getStatusColor(TaskStatus status) {
    switch (status) {
      case TaskStatus.waiting:
        return Colors.blueGrey;
      case TaskStatus.inProgress:
        return Colors.blueGrey[700]!;
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message, style: GoogleFonts.poppins())),
      );
    }
  }
}
