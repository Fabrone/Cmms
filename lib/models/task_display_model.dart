import 'package:cmms/models/task_status_model.dart';
import 'package:cmms/notifications/models/maintenance_task_model.dart';
import 'package:cmms/notifications/models/notification_model.dart';

class TaskDisplayModel {
  final String taskId;
  final String category;
  final String component;
  final String intervention;
  final int frequency;
  final DateTime? lastInspectionDate;
  final DateTime? nextInspectionDate;
  final DateTime? notificationDate;
  final TaskStatus status;
  final String? notes;
  final DateTime? createdAt;
  final bool hasNotification;

  TaskDisplayModel({
    required this.taskId,
    required this.category,
    required this.component,
    required this.intervention,
    required this.frequency,
    this.lastInspectionDate,
    this.nextInspectionDate,
    this.notificationDate,
    required this.status,
    this.notes,
    this.createdAt,
    required this.hasNotification,
  });

  factory TaskDisplayModel.fromMaintenanceTask(
    MaintenanceTaskModel maintenanceTask,
    String taskId, {
    NotificationModel? notification,
    TaskProgressModel? progress,
  }) {
    TaskStatus status = TaskStatus.waiting;
    
    if (progress != null) {
      status = progress.status;
    } else if (notification == null) {
      // No notification means no status tracking yet
      status = TaskStatus.waiting;
    }

    return TaskDisplayModel(
      taskId: taskId,
      category: maintenanceTask.category,
      component: maintenanceTask.component,
      intervention: maintenanceTask.intervention,
      frequency: maintenanceTask.frequency,
      lastInspectionDate: notification?.lastInspectionDate,
      nextInspectionDate: notification?.nextInspectionDate,
      notificationDate: notification?.notificationDate,
      status: status,
      notes: progress?.notes,
      createdAt: maintenanceTask.createdAt,
      hasNotification: notification != null,
    );
  }

  String get statusDisplay {
    if (!hasNotification) return '-';
    return status.displayName;
  }

  bool get canUpdateStatus {
    return hasNotification; // Can only update status if there's a notification
  }
}

class CategoryDisplayModel {
  final String category;
  final List<TaskDisplayModel> tasks;
  final TaskStatus overallStatus;
  final int totalTasks;
  final int waitingTasks;
  final int inProgressTasks;
  final int completedTasks;
  final int noStatusTasks;

  CategoryDisplayModel({
    required this.category,
    required this.tasks,
    required this.overallStatus,
    required this.totalTasks,
    required this.waitingTasks,
    required this.inProgressTasks,
    required this.completedTasks,
    required this.noStatusTasks,
  });

  factory CategoryDisplayModel.fromTasks(String category, List<TaskDisplayModel> tasks) {
    int totalTasks = tasks.length;
    int waitingTasks = 0;
    int inProgressTasks = 0;
    int completedTasks = 0;
    int noStatusTasks = 0;

    for (var task in tasks) {
      if (!task.hasNotification) {
        noStatusTasks++;
      } else {
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
    }

    // Calculate overall status
    TaskStatus overallStatus;
    if (completedTasks > 0 && waitingTasks == 0 && inProgressTasks == 0 && noStatusTasks == 0) {
      overallStatus = TaskStatus.completed;
    } else if (inProgressTasks > 0 || completedTasks > 0) {
      overallStatus = TaskStatus.inProgress;
    } else {
      overallStatus = TaskStatus.waiting;
    }

    return CategoryDisplayModel(
      category: category,
      tasks: tasks,
      overallStatus: overallStatus,
      totalTasks: totalTasks,
      waitingTasks: waitingTasks,
      inProgressTasks: inProgressTasks,
      completedTasks: completedTasks,
      noStatusTasks: noStatusTasks,
    );
  }
}