import 'package:cloud_firestore/cloud_firestore.dart';

class MaintenanceTaskModel {
  final String component;
  final String intervention;
  final String frequency;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final String? createdBy;

  MaintenanceTaskModel({
    required this.component,
    required this.intervention,
    required this.frequency,
    this.createdAt,
    this.updatedAt,
    this.createdBy,
  });

  // Convert model to a Map for Firestore
  Map<String, dynamic> toMap() {
    return {
      'component': component,
      'intervention': intervention,
      'frequency': frequency,
      'createdAt': createdAt != null ? Timestamp.fromDate(createdAt!) : FieldValue.serverTimestamp(),
      'updatedAt': updatedAt != null ? Timestamp.fromDate(updatedAt!) : FieldValue.serverTimestamp(),
      'createdBy': createdBy,
    };
  }

  // Create model from Firestore data
  factory MaintenanceTaskModel.fromMap(Map<String, dynamic> map) {
    return MaintenanceTaskModel(
      component: map['component'] ?? '',
      intervention: map['intervention'] ?? '',
      frequency: map['frequency'] ?? '',
      createdAt: map['createdAt'] != null 
          ? (map['createdAt'] as Timestamp).toDate() 
          : null,
      updatedAt: map['updatedAt'] != null 
          ? (map['updatedAt'] as Timestamp).toDate() 
          : null,
      createdBy: map['createdBy'],
    );
  }

  // Create a copy of the model with updated fields
  MaintenanceTaskModel copyWith({
    String? component,
    String? intervention,
    String? frequency,
    DateTime? createdAt,
    DateTime? updatedAt,
    String? createdBy,
  }) {
    return MaintenanceTaskModel(
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
