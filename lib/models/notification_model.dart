import 'package:cloud_firestore/cloud_firestore.dart';

class NotificationModel {
  final String id;
  final String taskId;
  final String category;
  final String component;
  final String intervention;
  final int frequency;
  final DateTime lastInspectionDate;
  final DateTime nextInspectionDate;
  final DateTime notificationDate;
  final bool isTriggered;
  final bool isCompleted;
  final List<String> assignedTechnicians;
  final DateTime createdAt;
  final String createdBy;

  NotificationModel({
    required this.id,
    required this.taskId,
    required this.category,
    required this.component,
    required this.intervention,
    required this.frequency,
    required this.lastInspectionDate,
    required this.nextInspectionDate,
    required this.notificationDate,
    this.isTriggered = false,
    this.isCompleted = false,
    required this.assignedTechnicians,
    required this.createdAt,
    required this.createdBy,
  });

  Map<String, dynamic> toMap() {
    return {
      'taskId': taskId,
      'category': category,
      'component': component,
      'intervention': intervention,
      'frequency': frequency,
      'lastInspectionDate': Timestamp.fromDate(lastInspectionDate),
      'nextInspectionDate': Timestamp.fromDate(nextInspectionDate),
      'notificationDate': Timestamp.fromDate(notificationDate),
      'isTriggered': isTriggered,
      'isCompleted': isCompleted,
      'assignedTechnicians': assignedTechnicians,
      'createdAt': Timestamp.fromDate(createdAt),
      'createdBy': createdBy,
    };
  }

  factory NotificationModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return NotificationModel(
      id: doc.id,
      taskId: data['taskId'] ?? '',
      category: data['category'] ?? '',
      component: data['component'] ?? '',
      intervention: data['intervention'] ?? '',
      frequency: data['frequency'] ?? 0,
      lastInspectionDate: (data['lastInspectionDate'] as Timestamp).toDate(),
      nextInspectionDate: (data['nextInspectionDate'] as Timestamp).toDate(),
      notificationDate: (data['notificationDate'] as Timestamp).toDate(),
      isTriggered: data['isTriggered'] ?? false,
      isCompleted: data['isCompleted'] ?? false,
      assignedTechnicians: List<String>.from(data['assignedTechnicians'] ?? []),
      createdAt: (data['createdAt'] as Timestamp).toDate(),
      createdBy: data['createdBy'] ?? '',
    );
  }

  NotificationModel copyWith({
    String? id,
    String? taskId,
    String? category,
    String? component,
    String? intervention,
    int? frequency,
    DateTime? lastInspectionDate,
    DateTime? nextInspectionDate,
    DateTime? notificationDate,
    bool? isTriggered,
    bool? isCompleted,
    List<String>? assignedTechnicians,
    DateTime? createdAt,
    String? createdBy,
  }) {
    return NotificationModel(
      id: id ?? this.id,
      taskId: taskId ?? this.taskId,
      category: category ?? this.category,
      component: component ?? this.component,
      intervention: intervention ?? this.intervention,
      frequency: frequency ?? this.frequency,
      lastInspectionDate: lastInspectionDate ?? this.lastInspectionDate,
      nextInspectionDate: nextInspectionDate ?? this.nextInspectionDate,
      notificationDate: notificationDate ?? this.notificationDate,
      isTriggered: isTriggered ?? this.isTriggered,
      isCompleted: isCompleted ?? this.isCompleted,
      assignedTechnicians: assignedTechnicians ?? this.assignedTechnicians,
      createdAt: createdAt ?? this.createdAt,
      createdBy: createdBy ?? this.createdBy,
    );
  }
}

class GroupedNotificationModel {
  final DateTime notificationDate;
  final List<NotificationModel> notifications;
  final bool isTriggered;

  GroupedNotificationModel({
    required this.notificationDate,
    required this.notifications,
    this.isTriggered = false,
  });

  Map<String, dynamic> toMap() {
    return {
      'notificationDate': Timestamp.fromDate(notificationDate),
      'notifications': notifications.map((n) => n.toMap()).toList(),
      'isTriggered': isTriggered,
      'taskCount': notifications.length,
      'categories': notifications.map((n) => n.category).toSet().toList(),
    };
  }

  factory GroupedNotificationModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    final notificationsList = data['notifications'] as List<dynamic>;
    
    return GroupedNotificationModel(
      notificationDate: (data['notificationDate'] as Timestamp).toDate(),
      notifications: notificationsList.map((n) {
        final notificationData = n as Map<String, dynamic>;
        return NotificationModel(
          id: doc.id,
          taskId: notificationData['taskId'] ?? '',
          category: notificationData['category'] ?? '',
          component: notificationData['component'] ?? '',
          intervention: notificationData['intervention'] ?? '',
          frequency: notificationData['frequency'] ?? 0,
          lastInspectionDate: (notificationData['lastInspectionDate'] as Timestamp).toDate(),
          nextInspectionDate: (notificationData['nextInspectionDate'] as Timestamp).toDate(),
          notificationDate: (notificationData['notificationDate'] as Timestamp).toDate(),
          isTriggered: notificationData['isTriggered'] ?? false,
          isCompleted: notificationData['isCompleted'] ?? false,
          assignedTechnicians: List<String>.from(notificationData['assignedTechnicians'] ?? []),
          createdAt: (notificationData['createdAt'] as Timestamp).toDate(),
          createdBy: notificationData['createdBy'] ?? '',
        );
      }).toList(),
      isTriggered: data['isTriggered'] ?? false,
    );
  }
}
