import 'package:cloud_firestore/cloud_firestore.dart';

class WorkOrder {
  final String id;
  final String workOrderId;
  final String? requestId;
  final String title;
  final String description;
  final String status;
  final String priority;
  final String assignedTo;
  final DateTime? createdAt;
  final List<String> attachments;
  final List<Map<String, dynamic>> history;
  final String clientStatus;
  final String clientNotes;

  WorkOrder({
    required this.id,
    required this.workOrderId,
    this.requestId,
    required this.title,
    required this.description,
    required this.status,
    required this.priority,
    required this.assignedTo,
    this.createdAt,
    required this.attachments,
    required this.history,
    required this.clientStatus,
    required this.clientNotes,
  });

  factory WorkOrder.fromSnapshot(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return WorkOrder(
      id: doc.id,
      workOrderId: data['workOrderId'] ?? '',
      requestId: data['requestId'],
      title: data['title'] ?? '',
      description: data['description'] ?? '',
      status: data['status'] ?? 'Open',
      priority: data['priority'] ?? 'Medium',
      assignedTo: data['assignedTo'] ?? '',
      createdAt: (data['createdAt'] as Timestamp?)?.toDate(),
      attachments: (data['attachments'] as List<dynamic>?)
          ?.map((item) => item.toString())
          .toList() ?? [],
      history: (data['history'] as List<dynamic>?)
          ?.map((item) => Map<String, dynamic>.from(item as Map))
          .toList() ?? [],
      clientStatus: data['clientStatus'] ?? 'Awaiting Client Action',
      clientNotes: data['clientNotes'] ?? '',
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'workOrderId': workOrderId,
      'requestId': requestId,
      'title': title,
      'description': description,
      'status': status,
      'priority': priority,
      'assignedTo': assignedTo,
      'createdAt': createdAt != null ? Timestamp.fromDate(createdAt!) : null,
      'attachments': attachments,
      'history': history,
      'clientStatus': clientStatus,
      'clientNotes': clientNotes,
    };
  }
}
