import 'package:cloud_firestore/cloud_firestore.dart';

class Request {
  final String id;
  final String requestId;
  final String title;
  final String description;
  final String status;
  final String priority;
  final DateTime? createdAt;
  final String createdBy;
  final String? createdByEmail;
  final List<Map<String, String>> attachments;
  final List<Map<String, dynamic>> comments;
  final List<String> workOrderIds;
  final String clientStatus;

  Request({
    required this.id,
    required this.requestId,
    required this.title,
    required this.description,
    required this.status,
    required this.priority,
    this.createdAt,
    required this.createdBy,
    this.createdByEmail,
    required this.attachments,
    required this.comments,
    required this.workOrderIds,
    required this.clientStatus,
  });

  factory Request.fromSnapshot(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return Request(
      id: doc.id,
      requestId: data['requestId'] ?? '',
      title: data['title'] ?? '',
      description: data['description'] ?? '',
      status: data['status'] ?? 'Open',
      priority: data['priority'] ?? 'Medium',
      createdAt: (data['createdAt'] as Timestamp?)?.toDate(),
      createdBy: data['createdBy'] ?? '',
      createdByEmail: data['createdByEmail'],
      attachments: (data['attachments'] as List<dynamic>?)
          ?.map((item) => Map<String, String>.from(item as Map))
          .toList() ?? [],
      comments: (data['comments'] as List<dynamic>?)
          ?.map((item) => Map<String, dynamic>.from(item as Map))
          .toList() ?? [],
      workOrderIds: (data['workOrderIds'] as List<dynamic>?)
          ?.map((item) => item.toString())
          .toList() ?? [],
      clientStatus: data['clientStatus'] ?? 'Pending',
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'requestId': requestId,
      'title': title,
      'description': description,
      'status': status,
      'priority': priority,
      'createdAt': createdAt != null ? Timestamp.fromDate(createdAt!) : null,
      'createdBy': createdBy,
      'createdByEmail': createdByEmail,
      'attachments': attachments,
      'comments': comments,
      'workOrderIds': workOrderIds,
      'clientStatus': clientStatus,
    };
  }
}
