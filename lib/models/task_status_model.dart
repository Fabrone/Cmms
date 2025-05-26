import 'package:cloud_firestore/cloud_firestore.dart';

enum TaskStatus {
  waiting,
  inProgress,
  completed,
}

extension TaskStatusExtension on TaskStatus {
  String get displayName {
    switch (this) {
      case TaskStatus.waiting:
        return 'Waiting';
      case TaskStatus.inProgress:
        return 'In Progress';
      case TaskStatus.completed:
        return 'Completed';
    }
  }

  String get value {
    switch (this) {
      case TaskStatus.waiting:
        return 'waiting';
      case TaskStatus.inProgress:
        return 'in_progress';
      case TaskStatus.completed:
        return 'completed';
    }
  }

  static TaskStatus fromString(String value) {
    switch (value.toLowerCase()) {
      case 'in_progress':
        return TaskStatus.inProgress;
      case 'completed':
        return TaskStatus.completed;
      default:
        return TaskStatus.waiting;
    }
  }
}

class TaskProgressModel {
  final String taskId;
  final String category;
  final String component;
  final String intervention;
  final TaskStatus status;
  final DateTime? startedAt;
  final DateTime? completedAt;
  final String? notes;
  final String? assignedTo;
  final DateTime updatedAt;

  TaskProgressModel({
    required this.taskId,
    required this.category,
    required this.component,
    required this.intervention,
    required this.status,
    this.startedAt,
    this.completedAt,
    this.notes,
    this.assignedTo,
    required this.updatedAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'taskId': taskId,
      'category': category,
      'component': component,
      'intervention': intervention,
      'status': status.value,
      'startedAt': startedAt != null ? Timestamp.fromDate(startedAt!) : null,
      'completedAt': completedAt != null ? Timestamp.fromDate(completedAt!) : null,
      'notes': notes,
      'assignedTo': assignedTo,
      'updatedAt': Timestamp.fromDate(updatedAt),
    };
  }

  factory TaskProgressModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return TaskProgressModel(
      taskId: data['taskId'] ?? '',
      category: data['category'] ?? '',
      component: data['component'] ?? '',
      intervention: data['intervention'] ?? '',
      status: TaskStatusExtension.fromString(data['status'] ?? 'waiting'),
      startedAt: data['startedAt'] != null ? (data['startedAt'] as Timestamp).toDate() : null,
      completedAt: data['completedAt'] != null ? (data['completedAt'] as Timestamp).toDate() : null,
      notes: data['notes'],
      assignedTo: data['assignedTo'],
      updatedAt: (data['updatedAt'] as Timestamp).toDate(),
    );
  }

  TaskProgressModel copyWith({
    String? taskId,
    String? category,
    String? component,
    String? intervention,
    TaskStatus? status,
    DateTime? startedAt,
    DateTime? completedAt,
    String? notes,
    String? assignedTo,
    DateTime? updatedAt,
  }) {
    return TaskProgressModel(
      taskId: taskId ?? this.taskId,
      category: category ?? this.category,
      component: component ?? this.component,
      intervention: intervention ?? this.intervention,
      status: status ?? this.status,
      startedAt: startedAt ?? this.startedAt,
      completedAt: completedAt ?? this.completedAt,
      notes: notes ?? this.notes,
      assignedTo: assignedTo ?? this.assignedTo,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}

class CategoryProgressModel {
  final String category;
  final TaskStatus status;
  final int totalTasks;
  final int waitingTasks;
  final int inProgressTasks;
  final int completedTasks;
  final DateTime updatedAt;

  CategoryProgressModel({
    required this.category,
    required this.status,
    required this.totalTasks,
    required this.waitingTasks,
    required this.inProgressTasks,
    required this.completedTasks,
    required this.updatedAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'category': category,
      'status': status.value,
      'totalTasks': totalTasks,
      'waitingTasks': waitingTasks,
      'inProgressTasks': inProgressTasks,
      'completedTasks': completedTasks,
      'updatedAt': Timestamp.fromDate(updatedAt),
    };
  }

  factory CategoryProgressModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return CategoryProgressModel(
      category: data['category'] ?? '',
      status: TaskStatusExtension.fromString(data['status'] ?? 'waiting'),
      totalTasks: data['totalTasks'] ?? 0,
      waitingTasks: data['waitingTasks'] ?? 0,
      inProgressTasks: data['inProgressTasks'] ?? 0,
      completedTasks: data['completedTasks'] ?? 0,
      updatedAt: (data['updatedAt'] as Timestamp).toDate(),
    );
  }

  static TaskStatus calculateCategoryStatus({
    required int waitingTasks,
    required int inProgressTasks,
    required int completedTasks,
  }) {
    if (completedTasks > 0 && waitingTasks == 0 && inProgressTasks == 0) {
      return TaskStatus.completed;
    } else if (inProgressTasks > 0 || completedTasks > 0) {
      return TaskStatus.inProgress;
    } else {
      return TaskStatus.waiting;
    }
  }
}
