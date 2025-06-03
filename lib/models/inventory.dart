import 'package:cloud_firestore/cloud_firestore.dart';

class InventoryItem {
  final String id;
  final String itemId;
  final String itemName;
  final int quantity;
  final int reorderPoint;
  final String category;
  final String locationId;
  final String notes;
  final DateTime? lastUpdated;
  final DateTime? createdAt;
  final String createdBy;
  final List<Map<String, dynamic>> history;

  InventoryItem({
    required this.id,
    required this.itemId,
    required this.itemName,
    required this.quantity,
    required this.reorderPoint,
    required this.category,
    required this.locationId,
    required this.notes,
    this.lastUpdated,
    this.createdAt,
    required this.createdBy,
    required this.history,
  });

  factory InventoryItem.fromSnapshot(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return InventoryItem(
      id: doc.id,
      itemId: data['itemId'] ?? '',
      itemName: data['itemName'] ?? '',
      quantity: data['quantity'] ?? 0,
      reorderPoint: data['reorderPoint'] ?? 0,
      category: data['category'] ?? 'General',
      locationId: data['locationId'] ?? '',
      notes: data['notes'] ?? '',
      lastUpdated: (data['lastUpdated'] as Timestamp?)?.toDate(),
      createdAt: (data['createdAt'] as Timestamp?)?.toDate(),
      createdBy: data['createdBy'] ?? '',
      history: (data['history'] as List<dynamic>?)
          ?.map((item) => Map<String, dynamic>.from(item as Map))
          .toList() ?? [],
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'itemId': itemId,
      'itemName': itemName,
      'quantity': quantity,
      'reorderPoint': reorderPoint,
      'category': category,
      'locationId': locationId,
      'notes': notes,
      'lastUpdated': lastUpdated != null ? Timestamp.fromDate(lastUpdated!) : null,
      'createdAt': createdAt != null ? Timestamp.fromDate(createdAt!) : null,
      'createdBy': createdBy,
      'history': history,
    };
  }

  bool get isLowStock => quantity <= reorderPoint;
}