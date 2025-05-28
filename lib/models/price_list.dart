import 'package:cloud_firestore/cloud_firestore.dart';

class PriceList {
  final String id;
  final String userId;
  final String title;
  final String fileName;
  final String downloadUrl;
  final DateTime? uploadedAt;
  final String facilityId;

  PriceList({
    required this.id,
    required this.userId,
    required this.title,
    required this.fileName,
    required this.downloadUrl,
    this.uploadedAt,
    required this.facilityId,
  });

  Map<String, dynamic> toJson() => {
        'userId': userId,
        'title': title,
        'fileName': fileName,
        'downloadUrl': downloadUrl,
        'uploadedAt': uploadedAt?.toIso8601String(),
        'facilityId': facilityId,
      };

  factory PriceList.fromJson(String id, Map<String, dynamic> json) => PriceList(
        id: id,
        userId: json['userId'] as String,
        title: json['title'] as String,
        fileName: json['fileName'] as String,
        downloadUrl: json['downloadUrl'] as String,
        uploadedAt: json['uploadedAt'] != null ? DateTime.parse(json['uploadedAt'] as String) : null,
        facilityId: json['facilityId'] as String,
      );

  factory PriceList.fromSnapshot(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return PriceList(
      id: doc.id,
      userId: data['userId'] as String,
      title: data['title'] as String,
      fileName: data['fileName'] as String,
      downloadUrl: data['downloadUrl'] as String,
      uploadedAt: (data['uploadedAt'] as Timestamp?)?.toDate(),
      facilityId: data['facilityId'] as String,
    );
  }
}