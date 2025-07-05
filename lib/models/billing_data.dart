import 'package:cloud_firestore/cloud_firestore.dart';

class BillingData {
  final String id;
  final String userId;
  final String title;
  final String fileName;
  final String downloadUrl;
  final DateTime? uploadedAt;
  final String facilityId;
  final String status; // pending, paid
  final String approvalStatus; // pending, approved, review (removed declined)
  final String? approvalNotes;
  final String? approvedBy;
  final DateTime? approvedAt;

  BillingData({
    required this.id,
    required this.userId,
    required this.title,
    required this.fileName,
    required this.downloadUrl,
    this.uploadedAt,
    required this.facilityId,
    required this.status,
    required this.approvalStatus,
    this.approvalNotes,
    this.approvedBy,
    this.approvedAt,
  });

  // Helper method to normalize legacy statuses
  String get normalizedApprovalStatus {
    if (approvalStatus.toLowerCase() == 'declined') {
      return 'review'; // Convert legacy declined to review
    }
    return approvalStatus;
  }

  factory BillingData.fromSnapshot(DocumentSnapshot snapshot) {
    final data = snapshot.data() as Map<String, dynamic>;
    return BillingData(
      id: snapshot.id,
      userId: data['userId'] ?? '',
      title: data['title'] ?? '',
      fileName: data['fileName'] ?? '',
      downloadUrl: data['downloadUrl'] ?? '',
      uploadedAt: data['uploadedAt'] != null 
          ? (data['uploadedAt'] as Timestamp).toDate()
          : null,
      facilityId: data['facilityId'] ?? '',
      status: data['status'] ?? 'pending',
      approvalStatus: data['approvalStatus'] ?? 'pending',
      approvalNotes: data['approvalNotes'],
      approvedBy: data['approvedBy'],
      approvedAt: data['approvedAt'] != null 
          ? (data['approvedAt'] as Timestamp).toDate()
          : null,
    );
  }

  factory BillingData.fromMap(Map<String, dynamic> data, String id) {
    return BillingData(
      id: id,
      userId: data['userId'] ?? '',
      title: data['title'] ?? '',
      fileName: data['fileName'] ?? '',
      downloadUrl: data['downloadUrl'] ?? '',
      uploadedAt: data['uploadedAt'] != null 
          ? (data['uploadedAt'] as Timestamp).toDate()
          : null,
      facilityId: data['facilityId'] ?? '',
      status: data['status'] ?? 'pending',
      approvalStatus: data['approvalStatus'] ?? 'pending',
      approvalNotes: data['approvalNotes'],
      approvedBy: data['approvedBy'],
      approvedAt: data['approvedAt'] != null 
          ? (data['approvedAt'] as Timestamp).toDate()
          : null,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'userId': userId,
      'title': title,
      'fileName': fileName,
      'downloadUrl': downloadUrl,
      'uploadedAt': uploadedAt != null ? Timestamp.fromDate(uploadedAt!) : null,
      'facilityId': facilityId,
      'status': status,
      'approvalStatus': approvalStatus,
      'approvalNotes': approvalNotes,
      'approvedBy': approvedBy,
      'approvedAt': approvedAt != null ? Timestamp.fromDate(approvedAt!) : null,
    };
  }

  BillingData copyWith({
    String? id,
    String? userId,
    String? title,
    String? fileName,
    String? downloadUrl,
    DateTime? uploadedAt,
    String? facilityId,
    String? status,
    String? approvalStatus,
    String? approvalNotes,
    String? approvedBy,
    DateTime? approvedAt,
  }) {
    return BillingData(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      title: title ?? this.title,
      fileName: fileName ?? this.fileName,
      downloadUrl: downloadUrl ?? this.downloadUrl,
      uploadedAt: uploadedAt ?? this.uploadedAt,
      facilityId: facilityId ?? this.facilityId,
      status: status ?? this.status,
      approvalStatus: approvalStatus ?? this.approvalStatus,
      approvalNotes: approvalNotes ?? this.approvalNotes,
      approvedBy: approvedBy ?? this.approvedBy,
      approvedAt: approvedAt ?? this.approvedAt,
    );
  }

  @override
  String toString() {
    return 'BillingData(id: $id, title: $title, status: $status, approvalStatus: $approvalStatus)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is BillingData && other.id == id;
  }

  @override
  int get hashCode => id.hashCode;
}
