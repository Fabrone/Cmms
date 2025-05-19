class MaintenanceTask {
  final String category;
  final String component;
  final String intervention;
  final int frequency;
  final String createdBy;
  final DateTime createdAt;

  MaintenanceTask({
    required this.category,
    required this.component,
    required this.intervention,
    required this.frequency,
    required this.createdBy,
    required this.createdAt,
  });

  Map<String, dynamic> toJson() => {
        'category': category,
        'component': component,
        'intervention': intervention,
        'frequency': frequency,
        'createdBy': createdBy,
        'createdAt': createdAt.toIso8601String(),
      };

  factory MaintenanceTask.fromJson(Map<String, dynamic> json) => MaintenanceTask(
        category: json['category'] as String,
        component: json['component'] as String,
        intervention: json['intervention'] as String,
        frequency: json['frequency'] as int,
        createdBy: json['createdBy'] as String,
        createdAt: DateTime.parse(json['createdAt'] as String),
      );
}