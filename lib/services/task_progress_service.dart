import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:logger/logger.dart';
import 'package:cmms/models/task_status_model.dart';

class TaskProgressService {
  static final TaskProgressService _instance = TaskProgressService._internal();
  factory TaskProgressService() => _instance;
  TaskProgressService._internal();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final Logger _logger = Logger();

  // Update task status
  Future<void> updateTaskStatus({
    required String taskId,
    required String category,
    required String component,
    required String intervention,
    required TaskStatus newStatus,
    String? notes,
  }) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) throw Exception('User not authenticated');

      final now = DateTime.now();
      DateTime? startedAt;
      DateTime? completedAt;

      // Set timestamps based on status
      if (newStatus == TaskStatus.inProgress) {
        startedAt = now;
      } else if (newStatus == TaskStatus.completed) {
        // Get existing startedAt if it exists
        final existingDoc = await _firestore.collection('TaskProgress').doc(taskId).get();
        if (existingDoc.exists) {
          final existingData = TaskProgressModel.fromFirestore(existingDoc);
          startedAt = existingData.startedAt ?? now;
        } else {
          startedAt = now;
        }
        completedAt = now;
      }

      final taskProgress = TaskProgressModel(
        taskId: taskId,
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

      // Update task progress
      await _firestore.collection('TaskProgress').doc(taskId).set(taskProgress.toMap());

      // Update category progress
      await _updateCategoryProgress(category);

      _logger.i('Task status updated: $taskId -> ${newStatus.displayName}');
    } catch (e) {
      _logger.e('Error updating task status: $e');
      rethrow;
    }
  }

  // Update category progress based on all tasks in that category
  Future<void> _updateCategoryProgress(String category) async {
    try {
      final tasksSnapshot = await _firestore
          .collection('TaskProgress')
          .where('category', isEqualTo: category)
          .get();

      int totalTasks = tasksSnapshot.docs.length;
      int waitingTasks = 0;
      int inProgressTasks = 0;
      int completedTasks = 0;

      for (var doc in tasksSnapshot.docs) {
        final task = TaskProgressModel.fromFirestore(doc);
        switch (task.status) {
          case TaskStatus.waiting:
            waitingTasks++;
            break;
          case TaskStatus.inProgress:
            inProgressTasks++;
            break;
          case TaskStatus.completed:
            completedTasks++;
            break;
        }
      }

      final categoryStatus = CategoryProgressModel.calculateCategoryStatus(
        waitingTasks: waitingTasks,
        inProgressTasks: inProgressTasks,
        completedTasks: completedTasks,
      );

      final categoryProgress = CategoryProgressModel(
        category: category,
        status: categoryStatus,
        totalTasks: totalTasks,
        waitingTasks: waitingTasks,
        inProgressTasks: inProgressTasks,
        completedTasks: completedTasks,
        updatedAt: DateTime.now(),
      );

      await _firestore.collection('CategoryProgress').doc(category).set(categoryProgress.toMap());

      _logger.i('Category progress updated: $category -> ${categoryStatus.displayName}');
    } catch (e) {
      _logger.e('Error updating category progress: $e');
    }
  }

  // Get tasks by category
  Stream<List<TaskProgressModel>> getTasksByCategory(String category) {
    return _firestore
        .collection('TaskProgress')
        .where('category', isEqualTo: category)
        .orderBy('updatedAt', descending: true)
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => TaskProgressModel.fromFirestore(doc))
            .toList());
  }

  // Get all categories with their progress
  Stream<List<CategoryProgressModel>> getCategoriesProgress() {
    return _firestore
        .collection('CategoryProgress')
        .orderBy('category')
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => CategoryProgressModel.fromFirestore(doc))
            .toList());
  }

  // Initialize task progress from maintenance tasks
  Future<void> initializeTasksFromMaintenanceTasks() async {
    try {
      final maintenanceTasksSnapshot = await _firestore.collection('Maintenance_Tasks').get();
      
      for (var doc in maintenanceTasksSnapshot.docs) {
        final taskData = doc.data();
        final taskId = doc.id;
        
        // Check if task progress already exists
        final existingProgress = await _firestore.collection('TaskProgress').doc(taskId).get();
        
        if (!existingProgress.exists) {
          // Create initial task progress
          final taskProgress = TaskProgressModel(
            taskId: taskId,
            category: taskData['category'] ?? '',
            component: taskData['component'] ?? '',
            intervention: taskData['intervention'] ?? '',
            status: TaskStatus.waiting,
            assignedTo: null,
            updatedAt: DateTime.now(),
          );
          
          await _firestore.collection('TaskProgress').doc(taskId).set(taskProgress.toMap());
        }
      }
      
      _logger.i('Task progress initialized from maintenance tasks');
    } catch (e) {
      _logger.e('Error initializing task progress: $e');
    }
  }

  // Get task progress by ID
  Future<TaskProgressModel?> getTaskProgress(String taskId) async {
    try {
      final doc = await _firestore.collection('TaskProgress').doc(taskId).get();
      if (doc.exists) {
        return TaskProgressModel.fromFirestore(doc);
      }
      return null;
    } catch (e) {
      _logger.e('Error getting task progress: $e');
      return null;
    }
  }
}
