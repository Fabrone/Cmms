import 'package:cloud_firestore/cloud_firestore.dart';

enum NotificationPriority { normal, urgent, critical }
enum NotificationType { automatic, custom, test, agent }
enum AlertType { notification, alert }

class NotificationReadInfo {
  final String userId;
  final String userName;
  final DateTime readAt;

  NotificationReadInfo({
    required this.userId,
    required this.userName,
    required this.readAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'userId': userId,
      'userName': userName,
      'readAt': Timestamp.fromDate(readAt),
    };
  }

  factory NotificationReadInfo.fromMap(Map<String, dynamic> map) {
    return NotificationReadInfo(
      userId: map['userId'] ?? '',
      userName: map['userName'] ?? 'Unknown User',
      readAt: (map['readAt'] as Timestamp).toDate(),
    );
  }
}

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
  final DateTime? alertDate; // 1 day before next inspection
  final bool isTriggered;
  final bool isCompleted;
  final bool isRead;
  final DateTime? triggeredAt;
  final DateTime? readAt;
  final List<String> assignedTechnicians;
  final DateTime createdAt;
  final String createdBy;
  final NotificationPriority priority;
  final NotificationType type;
  final AlertType alertType;
  final bool isAlert; // true if this is an alert, false if notification
  final int retryCount;
  final DateTime? lastRetryAt;
  final bool requiresAcknowledgment;

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
    this.alertDate,
    this.isTriggered = false,
    this.isCompleted = false,
    this.isRead = false,
    this.triggeredAt,
    this.readAt,
    required this.assignedTechnicians,
    required this.createdAt,
    required this.createdBy,
    this.priority = NotificationPriority.normal,
    this.type = NotificationType.custom,
    this.alertType = AlertType.notification,
    this.isAlert = false,
    this.retryCount = 0,
    this.lastRetryAt,
    this.requiresAcknowledgment = false,
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
      'alertDate': alertDate != null ? Timestamp.fromDate(alertDate!) : null,
      'isTriggered': isTriggered,
      'isCompleted': isCompleted,
      'isRead': isRead,
      'triggeredAt': triggeredAt != null ? Timestamp.fromDate(triggeredAt!) : null,
      'readAt': readAt != null ? Timestamp.fromDate(readAt!) : null,
      'assignedTechnicians': assignedTechnicians,
      'createdAt': Timestamp.fromDate(createdAt),
      'createdBy': createdBy,
      'priority': priority.name,
      'type': type.name,
      'alertType': alertType.name,
      'isAlert': isAlert,
      'retryCount': retryCount,
      'lastRetryAt': lastRetryAt != null ? Timestamp.fromDate(lastRetryAt!) : null,
      'requiresAcknowledgment': requiresAcknowledgment,
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
      alertDate: data['alertDate'] != null ? (data['alertDate'] as Timestamp).toDate() : null,
      isTriggered: data['isTriggered'] ?? false,
      isCompleted: data['isCompleted'] ?? false,
      isRead: data['isRead'] ?? false,
      triggeredAt: data['triggeredAt'] != null ? (data['triggeredAt'] as Timestamp).toDate() : null,
      readAt: data['readAt'] != null ? (data['readAt'] as Timestamp).toDate() : null,
      assignedTechnicians: List<String>.from(data['assignedTechnicians'] ?? []),
      createdAt: (data['createdAt'] as Timestamp).toDate(),
      createdBy: data['createdBy'] ?? '',
      priority: NotificationPriority.values.firstWhere(
        (e) => e.name == data['priority'],
        orElse: () => NotificationPriority.normal,
      ),
      type: NotificationType.values.firstWhere(
        (e) => e.name == data['type'],
        orElse: () => NotificationType.custom,
      ),
      alertType: AlertType.values.firstWhere(
        (e) => e.name == data['alertType'],
        orElse: () => AlertType.notification,
      ),
      isAlert: data['isAlert'] ?? false,
      retryCount: data['retryCount'] ?? 0,
      lastRetryAt: data['lastRetryAt'] != null ? (data['lastRetryAt'] as Timestamp).toDate() : null,
      requiresAcknowledgment: data['requiresAcknowledgment'] ?? false,
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
    DateTime? alertDate,
    bool? isTriggered,
    bool? isCompleted,
    bool? isRead,
    DateTime? triggeredAt,
    DateTime? readAt,
    List<String>? assignedTechnicians,
    DateTime? createdAt,
    String? createdBy,
    NotificationPriority? priority,
    NotificationType? type,
    AlertType? alertType,
    bool? isAlert,
    int? retryCount,
    DateTime? lastRetryAt,
    bool? requiresAcknowledgment,
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
      alertDate: alertDate ?? this.alertDate,
      isTriggered: isTriggered ?? this.isTriggered,
      isCompleted: isCompleted ?? this.isCompleted,
      isRead: isRead ?? this.isRead,
      triggeredAt: triggeredAt ?? this.triggeredAt,
      readAt: readAt ?? this.readAt,
      assignedTechnicians: assignedTechnicians ?? this.assignedTechnicians,
      createdAt: createdAt ?? this.createdAt,
      createdBy: createdBy ?? this.createdBy,
      priority: priority ?? this.priority,
      type: type ?? this.type,
      alertType: alertType ?? this.alertType,
      isAlert: isAlert ?? this.isAlert,
      retryCount: retryCount ?? this.retryCount,
      lastRetryAt: lastRetryAt ?? this.lastRetryAt,
      requiresAcknowledgment: requiresAcknowledgment ?? this.requiresAcknowledgment,
    );
  }
}

class GroupedNotificationModel {
  final String id;
  final DateTime notificationDate;
  final List<NotificationModel> notifications;
  final List<NotificationModel> alerts; // Separate alerts list
  final bool isTriggered;
  final bool isRead;
  final DateTime? triggeredAt;
  final DateTime? readAt;
  final List<NotificationReadInfo> readByUsers;
  final NotificationType type;
  final NotificationPriority priority;
  final int retryCount;
  final DateTime? lastRetryAt;
  final DateTime? expiryDate; // For custom notifications cleanup

  GroupedNotificationModel({
    required this.id,
    required this.notificationDate,
    required this.notifications,
    this.alerts = const [],
    this.isTriggered = false,
    this.isRead = false,
    this.triggeredAt,
    this.readAt,
    this.readByUsers = const [],
    this.type = NotificationType.custom,
    this.priority = NotificationPriority.normal,
    this.retryCount = 0,
    this.lastRetryAt,
    this.expiryDate,
  });

  Map<String, dynamic> toMap() {
    return {
      'notificationDate': Timestamp.fromDate(notificationDate),
      'notifications': notifications.map((n) => n.toMap()).toList(),
      'alerts': alerts.map((a) => a.toMap()).toList(),
      'isTriggered': isTriggered,
      'isRead': isRead,
      'triggeredAt': triggeredAt != null ? Timestamp.fromDate(triggeredAt!) : null,
      'readAt': readAt != null ? Timestamp.fromDate(readAt!) : null,
      'readByUsers': readByUsers.map((r) => r.toMap()).toList(),
      'taskCount': notifications.length,
      'alertCount': alerts.length,
      'categories': notifications.map((n) => n.category).toSet().toList(),
      'type': type.name,
      'priority': priority.name,
      'retryCount': retryCount,
      'lastRetryAt': lastRetryAt != null ? Timestamp.fromDate(lastRetryAt!) : null,
      'expiryDate': expiryDate != null ? Timestamp.fromDate(expiryDate!) : null,
    };
  }

  factory GroupedNotificationModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    final notificationsList = data['notifications'] as List<dynamic>? ?? [];
    final alertsList = data['alerts'] as List<dynamic>? ?? [];
    final readByUsersList = data['readByUsers'] as List<dynamic>? ?? [];

    return GroupedNotificationModel(
      id: doc.id,
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
          alertDate: notificationData['alertDate'] != null ? (notificationData['alertDate'] as Timestamp).toDate() : null,
          isTriggered: notificationData['isTriggered'] ?? false,
          isCompleted: notificationData['isCompleted'] ?? false,
          isRead: notificationData['isRead'] ?? false,
          triggeredAt: notificationData['triggeredAt'] != null ? (notificationData['triggeredAt'] as Timestamp).toDate() : null,
          readAt: notificationData['readAt'] != null ? (notificationData['readAt'] as Timestamp).toDate() : null,
          assignedTechnicians: List<String>.from(notificationData['assignedTechnicians'] ?? []),
          createdAt: (notificationData['createdAt'] as Timestamp).toDate(),
          createdBy: notificationData['createdBy'] ?? '',
          priority: NotificationPriority.values.firstWhere(
            (e) => e.name == notificationData['priority'],
            orElse: () => NotificationPriority.normal,
          ),
          type: NotificationType.values.firstWhere(
            (e) => e.name == notificationData['type'],
            orElse: () => NotificationType.custom,
          ),
          alertType: AlertType.values.firstWhere(
            (e) => e.name == notificationData['alertType'],
            orElse: () => AlertType.notification,
          ),
          isAlert: notificationData['isAlert'] ?? false,
        );
      }).toList(),
      alerts: alertsList.map((a) {
        final alertData = a as Map<String, dynamic>;
        return NotificationModel(
          id: doc.id,
          taskId: alertData['taskId'] ?? '',
          category: alertData['category'] ?? '',
          component: alertData['component'] ?? '',
          intervention: alertData['intervention'] ?? '',
          frequency: alertData['frequency'] ?? 0,
          lastInspectionDate: (alertData['lastInspectionDate'] as Timestamp).toDate(),
          nextInspectionDate: (alertData['nextInspectionDate'] as Timestamp).toDate(),
          notificationDate: (alertData['notificationDate'] as Timestamp).toDate(),
          alertDate: alertData['alertDate'] != null ? (alertData['alertDate'] as Timestamp).toDate() : null,
          isTriggered: alertData['isTriggered'] ?? false,
          isCompleted: alertData['isCompleted'] ?? false,
          isRead: alertData['isRead'] ?? false,
          triggeredAt: alertData['triggeredAt'] != null ? (alertData['triggeredAt'] as Timestamp).toDate() : null,
          readAt: alertData['readAt'] != null ? (alertData['readAt'] as Timestamp).toDate() : null,
          assignedTechnicians: List<String>.from(alertData['assignedTechnicians'] ?? []),
          createdAt: (alertData['createdAt'] as Timestamp).toDate(),
          createdBy: alertData['createdBy'] ?? '',
          priority: NotificationPriority.urgent, // Alerts are always urgent
          type: NotificationType.values.firstWhere(
            (e) => e.name == alertData['type'],
            orElse: () => NotificationType.custom,
          ),
          alertType: AlertType.alert,
          isAlert: true,
        );
      }).toList(),
      isTriggered: data['isTriggered'] ?? false,
      isRead: data['isRead'] ?? false,
      triggeredAt: data['triggeredAt'] != null ? (data['triggeredAt'] as Timestamp).toDate() : null,
      readAt: data['readAt'] != null ? (data['readAt'] as Timestamp).toDate() : null,
      readByUsers: readByUsersList.map((r) => NotificationReadInfo.fromMap(r as Map<String, dynamic>)).toList(),
      type: NotificationType.values.firstWhere(
        (e) => e.name == data['type'],
        orElse: () => NotificationType.custom,
      ),
      priority: NotificationPriority.values.firstWhere(
        (e) => e.name == data['priority'],
        orElse: () => NotificationPriority.normal,
      ),
      retryCount: data['retryCount'] ?? 0,
      lastRetryAt: data['lastRetryAt'] != null ? (data['lastRetryAt'] as Timestamp).toDate() : null,
      expiryDate: data['expiryDate'] != null ? (data['expiryDate'] as Timestamp).toDate() : null,
    );
  }

  // Helper methods
  bool get hasAlerts => alerts.isNotEmpty;
  bool get isExpired => expiryDate != null && DateTime.now().isAfter(expiryDate!);
  bool get needsRetry => !isTriggered && retryCount < 5 && 
    (lastRetryAt == null || DateTime.now().difference(lastRetryAt!).inMinutes > 15);
  
  List<NotificationModel> get allItems => [...notifications, ...alerts];
  int get totalCount => notifications.length + alerts.length;
}
