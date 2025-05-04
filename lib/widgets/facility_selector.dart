import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class FacilitySelector extends StatefulWidget {
  final String? facilityId;
  final Widget Function(String facilityId) childBuilder;

  const FacilitySelector({
    super.key,
    this.facilityId,
    required this.childBuilder,
  });

  @override
  State<FacilitySelector> createState() => _FacilitySelectorState();
}

class _FacilitySelectorState extends State<FacilitySelector> {
  String? _selectedFacilityId;

  @override
  void initState() {
    super.initState();
    _selectedFacilityId = widget.facilityId;
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance.collection('facilities').snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(child: Text('Error: ${snapshot.error}'));
        }
        final facilities = snapshot.data!.docs;
        if (facilities.isEmpty) {
          return const Center(child: Text('No facilities available'));
        }

        // Set default facility ID if not selected
        _selectedFacilityId ??= facilities.first.id;

        // Find the selected facility, fallback to first without lambda mismatch
        QueryDocumentSnapshot selectedFacility;
        try {
          selectedFacility = facilities.firstWhere(
            (doc) => doc.id == _selectedFacilityId,
            orElse: () => facilities.first,
          );
        } catch (e) {
          // Fallback in case of type issues
          selectedFacility = facilities.first;
        }

        debugPrint('Facility: id=${selectedFacility.id}, data=${selectedFacility.data()}');

        return widget.childBuilder(_selectedFacilityId!);
      },
    );
  }
}