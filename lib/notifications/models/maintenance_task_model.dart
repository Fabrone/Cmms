import 'package:cloud_firestore/cloud_firestore.dart';

class MaintenanceTaskModel {
  final String category;
  final String component;
  final String intervention;
  final int frequency; // in months
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final String? createdBy;

  MaintenanceTaskModel({
    required this.category,
    required this.component,
    required this.intervention,
    required this.frequency,
    this.createdAt,
    this.updatedAt,
    this.createdBy,
  });

  // Convert model to a Map for Firestore (without category since it's the doc ID)
  Map<String, dynamic> toMap() {
    return {
      'category': category, // Keep category as a field for querying
      'component': component,
      'intervention': intervention,
      'frequency': frequency,
      'createdAt': createdAt ?? DateTime.now(),
      'updatedAt': updatedAt ?? DateTime.now(),
      'createdBy': createdBy,
    };
  }

  // Create model from Firestore data
  factory MaintenanceTaskModel.fromMap(Map<String, dynamic> map) {
    return MaintenanceTaskModel(
      category: map['category'] ?? '',
      component: map['component'] ?? '',
      intervention: map['intervention'] ?? '',
      frequency: map['frequency'] ?? 0,
      createdAt: map['createdAt'] != null 
          ? (map['createdAt'] is Timestamp 
              ? (map['createdAt'] as Timestamp).toDate() 
              : map['createdAt'] as DateTime)
          : null,
      updatedAt: map['updatedAt'] != null 
          ? (map['updatedAt'] is Timestamp 
              ? (map['updatedAt'] as Timestamp).toDate() 
              : map['updatedAt'] as DateTime)
          : null,
      createdBy: map['createdBy'],
    );
  }

  // Create model from Firestore document
  factory MaintenanceTaskModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};
    return MaintenanceTaskModel.fromMap(data);
  }

  // Create a copy of the model with updated fields
  MaintenanceTaskModel copyWith({
    String? category,
    String? component,
    String? intervention,
    int? frequency,
    DateTime? createdAt,
    DateTime? updatedAt,
    String? createdBy,
  }) {
    return MaintenanceTaskModel(
      category: category ?? this.category,
      component: component ?? this.component,
      intervention: intervention ?? this.intervention,
      frequency: frequency ?? this.frequency,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      createdBy: createdBy ?? this.createdBy,
    );
  }
}

class CategoryModel {
  final String id;
  final List<MaintenanceTaskModel> tasks;
  final DateTime? createdAt;
  final String? createdBy;

  CategoryModel({
    required this.id,
    required this.tasks,
    this.createdAt,
    this.createdBy,
  });

  // Convert model to a Map for Firestore
  Map<String, dynamic> toMap() {
    return {
      'tasks': tasks.map((task) => task.toMap()).toList(),
      'createdAt': createdAt != null ? Timestamp.fromDate(createdAt!) : FieldValue.serverTimestamp(),
      'createdBy': createdBy,
    };
  }

  // Create model from Firestore data
  factory CategoryModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};
    final List<dynamic> tasksList = data['tasks'] ?? [];
    
    return CategoryModel(
      id: doc.id,
      tasks: tasksList.map((task) => MaintenanceTaskModel.fromMap(task as Map<String, dynamic>)).toList(),
      createdAt: data['createdAt'] != null 
          ? (data['createdAt'] as Timestamp).toDate() 
          : null,
      createdBy: data['createdBy'],
    );
  }
}

class CategoryInfo {
  final String category;
  final int frequency;
  final List<MaintenanceTaskModel> tasks;
  bool isSelected;

  CategoryInfo({
    required this.category,
    required this.frequency,
    required this.tasks,
    this.isSelected = false,
  });
}
