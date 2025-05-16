import 'package:cloud_firestore/cloud_firestore.dart';

class Facility {
  final String id;
  final String name;
  final String location;
  final String? address;
  final DateTime createdAt;

  Facility({
    required this.id,
    required this.name,
    required this.location,
    this.address,
    required this.createdAt,
  });

  factory Facility.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return Facility(
      id: doc.id,
      name: data['name'] ?? '',
      location: data['location'] ?? '',
      address: data['address'],
      createdAt: (data['createdAt'] as Timestamp).toDate(),
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'name': name,
      'location': location,
      'address': address,
      'createdAt': Timestamp.fromDate(createdAt),
    };
  }
}