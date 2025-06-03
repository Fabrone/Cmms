import 'package:cloud_firestore/cloud_firestore.dart';

class Equipment {
  final String id;
  final String equipmentId;
  final String name;
  final String type;
  final String serialNumber;
  final String locationId;
  final double purchasePrice;
  final DateTime? purchaseDate;
  final int warrantyMonths;
  final String status;
  final String notes;
  final List<Map<String, String>> attachments;
  final List<Map<String, dynamic>> maintenanceHistory;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final String createdBy;

  Equipment({
    required this.id,
    required this.equipmentId,
    required this.name,
    required this.type,
    required this.serialNumber,
    required this.locationId,
    required this.purchasePrice,
    this.purchaseDate,
    required this.warrantyMonths,
    required this.status,
    required this.notes,
    required this.attachments,
    required this.maintenanceHistory,
    this.createdAt,
    this.updatedAt,
    required this.createdBy,
  });

  factory Equipment.fromSnapshot(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return Equipment(
      id: doc.id,
      equipmentId: data['equipmentId'] ?? '',
      name: data['name'] ?? '',
      type: data['type'] ?? '',
      serialNumber: data['serialNumber'] ?? '',
      locationId: data['locationId'] ?? '',
      purchasePrice: (data['purchasePrice'] ?? 0.0).toDouble(),
      purchaseDate: (data['purchaseDate'] as Timestamp?)?.toDate(),
      warrantyMonths: data['warrantyMonths'] ?? 0,
      status: data['status'] ?? 'Active',
      notes: data['notes'] ?? '',
      attachments: (data['attachments'] as List<dynamic>?)
          ?.map((item) => Map<String, String>.from(item as Map))
          .toList() ?? [],
      maintenanceHistory: (data['maintenanceHistory'] as List<dynamic>?)
          ?.map((item) => Map<String, dynamic>.from(item as Map))
          .toList() ?? [],
      createdAt: (data['createdAt'] as Timestamp?)?.toDate(),
      updatedAt: (data['updatedAt'] as Timestamp?)?.toDate(),
      createdBy: data['createdBy'] ?? '',
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'equipmentId': equipmentId,
      'name': name,
      'type': type,
      'serialNumber': serialNumber,
      'locationId': locationId,
      'purchasePrice': purchasePrice,
      'purchaseDate': purchaseDate != null ? Timestamp.fromDate(purchaseDate!) : null,
      'warrantyMonths': warrantyMonths,
      'status': status,
      'notes': notes,
      'attachments': attachments,
      'maintenanceHistory': maintenanceHistory,
      'createdAt': createdAt != null ? Timestamp.fromDate(createdAt!) : null,
      'updatedAt': updatedAt != null ? Timestamp.fromDate(updatedAt!) : null,
      'createdBy': createdBy,
    };
  }
}