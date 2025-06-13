import 'package:cloud_firestore/cloud_firestore.dart';

class Vendor {
  final String id;
  final String vendorId;
  final String name;
  final String contact;
  final String email;
  final String phone;
  final String services;
  final String contractDetails;
  final String category;
  final double rating;
  final String status;
  final List<Map<String, dynamic>> serviceHistory;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final String createdBy;
  final String userId;
  final String facilityId;

  Vendor({
    required this.id,
    required this.vendorId,
    required this.name,
    required this.contact,
    required this.email,
    required this.phone,
    required this.services,
    required this.contractDetails,
    required this.category,
    required this.rating,
    required this.status,
    required this.serviceHistory,
    this.createdAt,
    this.updatedAt,
    required this.createdBy,
    required this.userId,
    required this.facilityId,
  });

  factory Vendor.fromSnapshot(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return Vendor(
      id: doc.id,
      vendorId: data['vendorId'] ?? '',
      name: data['name'] ?? '',
      contact: data['contact'] ?? '',
      email: data['email'] ?? '',
      phone: data['phone'] ?? '',
      services: data['services'] ?? '',
      contractDetails: data['contractDetails'] ?? '',
      category: data['category'] ?? 'General',
      rating: (data['rating'] ?? 0.0).toDouble(),
      status: data['status'] ?? 'Active',
      serviceHistory: (data['serviceHistory'] as List<dynamic>?)
          ?.map((item) => Map<String, dynamic>.from(item as Map))
          .toList() ??
          [],
      createdAt: (data['createdAt'] as Timestamp?)?.toDate(),
      updatedAt: (data['updatedAt'] as Timestamp?)?.toDate(),
      createdBy: data['createdBy'] ?? '',
      userId: data['userId'] ?? '',
      facilityId: data['facilityId'] ?? '',
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'vendorId': vendorId,
      'name': name,
      'contact': contact,
      'email': email,
      'phone': phone,
      'services': services,
      'contractDetails': contractDetails,
      'category': category,
      'rating': rating,
      'status': status,
      'serviceHistory': serviceHistory,
      'createdAt': createdAt != null ? Timestamp.fromDate(createdAt!) : null,
      'updatedAt': updatedAt != null ? Timestamp.fromDate(updatedAt!) : null,
      'createdBy': createdBy,
      'userId': userId,
      'facilityId': facilityId,
    };
  }
}