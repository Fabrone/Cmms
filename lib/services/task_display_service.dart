import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cmms/notifications/models/notification_model.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:logger/logger.dart';
import 'package:cmms/models/task_display_model.dart';
import 'package:cmms/models/task_status_model.dart';
import 'package:cmms/notifications/models/maintenance_task_model.dart';

class TaskDisplayService {
  static final TaskDisplayService _instance = TaskDisplayService._internal();
  factory TaskDisplayService() => _instance;
  TaskDisplayService._internal();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final Logger _logger = Logger();

  // Get all categories with their tasks
  Stream<List<CategoryDisplayModel>> getCategoriesWithTasks() {
    return _firestore
        .collection('Maintenance_Tasks')
        .snapshots()
        .asyncMap((maintenanceSnapshot) async {
      
      // Get all notifications to match with maintenance tasks
      final notificationsSnapshot = await _firestore.collection('Notifications').get();
      final taskProgressSnapshot = await _firestore.collection('TaskProgress').get();
      
      // Create maps for quick lookup
      Map<String, NotificationModel> notificationMap = {};
      Map<String, TaskProgressModel> progressMap = {};
      
      // Process notifications (they might be grouped)
      for (var notificationDoc in notificationsSnapshot.docs) {
        try {
          final groupedNotification = GroupedNotificationModel.fromFirestore(notificationDoc);
          for (var notification in groupedNotification.notifications) {
            // Create a unique key for matching
            String key = '${notification.category}_${notification.component}_${notification.intervention}';
            notificationMap[key] = notification;
          }
        } catch (e) {
          _logger.w('Error processing notification ${notificationDoc.id}: $e');
        }
      }
      
      // Process task progress
      for (var progressDoc in taskProgressSnapshot.docs) {
        try {
          final progress = TaskProgressModel.fromFirestore(progressDoc);
          String key = '${progress.category}_${progress.component}_${progress.intervention}';
          progressMap[key] = progress;
        } catch (e) {
          _logger.w('Error processing task progress ${progressDoc.id}: $e');
        }
      }
      
      // Group maintenance tasks by category
      Map<String, List<TaskDisplayModel>> categorizedTasks = {};
      
      for (var maintenanceDoc in maintenanceSnapshot.docs) {
        try {
          final maintenanceTask = MaintenanceTaskModel.fromFirestore(maintenanceDoc);
          final taskId = maintenanceDoc.id;
          
          // Create lookup key
          String key = '${maintenanceTask.category}_${maintenanceTask.component}_${maintenanceTask.intervention}';
          
          // Find matching notification and progress
          final notification = notificationMap[key];
          final progress = progressMap[key];
          
          // Create task display model
          final taskDisplay = TaskDisplayModel.fromMaintenanceTask(
            maintenanceTask,
            taskId,
            notification: notification,
            progress: progress,
          );
          
          // Group by category
          if (!categorizedTasks.containsKey(maintenanceTask.category)) {
            categorizedTasks[maintenanceTask.category] = [];
          }
          categorizedTasks[maintenanceTask.category]!.add(taskDisplay);
          
        } catch (e) {
          _logger.w('Error processing maintenance task ${maintenanceDoc.id}: $e');
        }
      }
      
      // Convert to CategoryDisplayModel list
      List<CategoryDisplayModel> categories = [];
      categorizedTasks.forEach((category, tasks) {
        categories.add(CategoryDisplayModel.fromTasks(category, tasks));
      });
      
      // Sort categories alphabetically
      categories.sort((a, b) => a.category.compareTo(b.category));
      
      return categories;
    });
  }

  // Update task status in notifications
  Future<void> updateTaskStatus({
    required String category,
    required String component,
    required String intervention,
    required TaskStatus newStatus,
    String? notes,
  }) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) throw Exception('User not authenticated');

      // Find the notification containing this task
      final notificationsSnapshot = await _firestore.collection('Notifications').get();
      
      for (var notificationDoc in notificationsSnapshot.docs) {
        try {
          final groupedNotification = GroupedNotificationModel.fromFirestore(notificationDoc);
          
          // Check if this notification contains our task
          bool containsTask = groupedNotification.notifications.any((notification) =>
              notification.category == category &&
              notification.component == component &&
              notification.intervention == intervention);
          
          if (containsTask) {
            // Found the notification containing our task - update TaskProgress collection
            
            // Update TaskProgress collection
            String taskKey = '${category}_${component}_$intervention';
            await _updateTaskProgress(taskKey, category, component, intervention, newStatus, notes);
            
            _logger.i('Task status updated: $category -> $component -> ${newStatus.displayName}');
            return;
          }
        } catch (e) {
          _logger.w('Error processing notification ${notificationDoc.id}: $e');
        }
      }
      
      // If no notification found, still update TaskProgress for consistency
      String taskKey = '${category}_${component}_$intervention';
      await _updateTaskProgress(taskKey, category, component, intervention, newStatus, notes);
      
    } catch (e) {
      _logger.e('Error updating task status: $e');
      rethrow;
    }
  }

  Future<void> _updateTaskProgress(
    String taskKey,
    String category,
    String component,
    String intervention,
    TaskStatus newStatus,
    String? notes,
  ) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final now = DateTime.now();
    DateTime? startedAt;
    DateTime? completedAt;

    // Set timestamps based on status
    if (newStatus == TaskStatus.inProgress) {
      startedAt = now;
    } else if (newStatus == TaskStatus.completed) {
      // Get existing startedAt if it exists
      final existingDoc = await _firestore.collection('TaskProgress').doc(taskKey).get();
      if (existingDoc.exists) {
        final existingData = TaskProgressModel.fromFirestore(existingDoc);
        startedAt = existingData.startedAt ?? now;
      } else {
        startedAt = now;
      }
      completedAt = now;
    }

    final taskProgress = TaskProgressModel(
      taskId: taskKey,
      category: category,
      component: component,
      intervention: intervention,
      status: newStatus,
      startedAt: startedAt,
      completedAt: completedAt,
      notes: notes,
      assignedTo: user.uid,
      updatedAt: now,
    );

    await _firestore.collection('TaskProgress').doc(taskKey).set(taskProgress.toMap());
  }
}
