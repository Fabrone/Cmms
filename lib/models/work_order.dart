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
  final String assignedToEmail;
  final DateTime? createdAt;
  final String createdBy;
  final String createdByEmail;
  final String facilityId;
  final List<Map<String, String>> attachments;
  final List<Map<String, dynamic>> history;
  final String clientStatus; // Approved, To be Reviewed (Declined removed)
  final String clientNotes;
  final DateTime? clientActionDate;

  WorkOrder({
    required this.id,
    required this.workOrderId,
    this.requestId,
    required this.title,
    required this.description,
    required this.status,
    required this.priority,
    required this.assignedTo,
    required this.assignedToEmail,
    this.createdAt,
    required this.createdBy,
    required this.createdByEmail,
    required this.facilityId,
    required this.attachments,
    required this.history,
    required this.clientStatus,
    required this.clientNotes,
    this.clientActionDate,
  });

  factory WorkOrder.fromSnapshot(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return WorkOrder.fromMap(data, doc.id);
  }

  factory WorkOrder.fromMap(Map<String, dynamic> data, String id) {
    // Handle legacy "Declined" status by converting to "To be Reviewed"
    String clientStatus = data['clientStatus'] ?? 'To be Reviewed';
    if (clientStatus == 'Declined') {
      clientStatus = 'To be Reviewed';
    }

    return WorkOrder(
      id: id,
      workOrderId: data['workOrderId'] ?? id,
      requestId: data['requestId'],
      title: data['title'] ?? '',
      description: data['description'] ?? '',
      status: data['status'] ?? 'Open',
      priority: data['priority'] ?? 'Medium',
      assignedTo: data['assignedTo'] ?? '',
      assignedToEmail: data['assignedToEmail'] ?? '',
      createdAt: (data['createdAt'] as Timestamp?)?.toDate(),
      createdBy: data['createdBy'] ?? '',
      createdByEmail: data['createdByEmail'] ?? '',
      facilityId: data['facilityId'] ?? '',
      attachments: (data['attachments'] as List<dynamic>?)
          ?.map((item) => Map<String, String>.from(item as Map))
          .toList() ?? [],
      history: (data['history'] as List<dynamic>?)
          ?.map((item) => Map<String, dynamic>.from(item as Map))
          .toList() ?? [],
      clientStatus: clientStatus,
      clientNotes: data['clientNotes'] ?? '',
      clientActionDate: (data['clientActionDate'] as Timestamp?)?.toDate(),
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
      'assignedToEmail': assignedToEmail,
      'createdAt': createdAt != null ? Timestamp.fromDate(createdAt!) : null,
      'createdBy': createdBy,
      'createdByEmail': createdByEmail,
      'facilityId': facilityId,
      'attachments': attachments,
      'history': history,
      'clientStatus': clientStatus,
      'clientNotes': clientNotes,
      'clientActionDate': clientActionDate != null ? Timestamp.fromDate(clientActionDate!) : null,
    };
  }
}