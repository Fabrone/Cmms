import 'package:cloud_firestore/cloud_firestore.dart';

class Facility {
  final String id;
  final String name;
  final String location;
  final String? address;
  final String organization;
  final DateTime createdAt;
  final String createdBy;

  Facility({
    required this.id,
    required this.name,
    required this.location,
    this.address,
    required this.organization,
    required this.createdAt,
    required this.createdBy,
  });

  factory Facility.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return Facility(
      id: doc.id,
      name: data['name'] ?? '',
      location: data['location'] ?? '',
      address: data['address'],
      organization: data['organization'] ?? 'Embassy', 
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      createdBy: data['createdBy'] ?? '',
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'name': name,
      'location': location,
      'address': address,
      'organization': organization,
      'createdAt': Timestamp.fromDate(createdAt),
      'createdBy': createdBy,
    };
  }
}