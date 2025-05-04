import 'package:cloud_firestore/cloud_firestore.dart';

class UserModel {
  final String id;
  final String username;
  final String email;
  final DateTime createdAt;
  final bool isInvited;

  UserModel({
    required this.id,
    required this.username,
    required this.email,
    required this.createdAt,
    required this.isInvited,
  });

  // Convert UserModel to Firestore-compatible map
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'username': username,
      'email': email,
      'createdAt': createdAt,
      'isInvited': isInvited,
    };
  }

  // Create UserModel from Firestore document
  factory UserModel.fromMap(Map<String, dynamic> map) {
    return UserModel(
      id: map['id'] ?? '',
      username: map['username'] ?? '',
      email: map['email'] ?? '',
      createdAt: (map['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      isInvited: map['isInvited'] ?? false,
    );
  }
}