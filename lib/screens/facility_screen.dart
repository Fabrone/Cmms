import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:logger/logger.dart';
import 'package:google_fonts/google_fonts.dart';

class FacilityScreen extends StatefulWidget {
  final String facilityId;

  const FacilityScreen({
    super.key,
    required this.facilityId,
  });

  @override
  State<FacilityScreen> createState() => _FacilityScreenState();
}

class _FacilityScreenState extends State<FacilityScreen> {
  final _nameController = TextEditingController();
  final _addressController = TextEditingController();
  final Logger _logger = Logger();
  final GlobalKey<ScaffoldMessengerState> _messengerKey = GlobalKey<ScaffoldMessengerState>();

  Future<void> _addFacility() async {
    if (_nameController.text.isEmpty || _addressController.text.isEmpty) {
      _logger.w('Name or address empty');
      _messengerKey.currentState?.showSnackBar(
        const SnackBar(content: Text('Please enter name and address')),
      );
      return;
    }

    try {
      final ref = await FirebaseFirestore.instance.collection('facilities').add({
        'name': _nameController.text.trim(),
        'address': _addressController.text.trim(),
        'createdAt': Timestamp.now(),
      });

      _logger.i('Facility added: ${ref.id}');
      _nameController.clear();
      _addressController.clear();
      if (mounted) {
        _messengerKey.currentState?.showSnackBar(
          const SnackBar(content: Text('Facility added successfully')),
        );
        // Navigate to HomeScreen with the new facility ID
        Navigator.pushReplacementNamed(
          context,
          '/home',
          arguments: ref.id,
        );
      }
    } catch (e, stackTrace) {
      _logger.e('Error adding facility: $e', stackTrace: stackTrace);
      if (mounted) {
        _messengerKey.currentState?.showSnackBar(
          SnackBar(content: Text('Error adding facility: $e')),
        );
      }
    }
  }

  Future<void> _deleteFacility(String facilityId) async {
    try {
      await FirebaseFirestore.instance.collection('facilities').doc(facilityId).delete();
      _logger.i('Facility deleted: $facilityId');

      // If the deleted facility was selected, stay on FacilityScreen
      if (facilityId == widget.facilityId) {
        _messengerKey.currentState?.showSnackBar(
          const SnackBar(content: Text('Facility deleted successfully')),
        );
      }
    } catch (e, stackTrace) {
      _logger.e('Error deleting facility: $e', stackTrace: stackTrace);
      if (mounted) {
        _messengerKey.currentState?.showSnackBar(
          SnackBar(content: Text('Error deleting facility: $e')),
        );
      }
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _addressController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ScaffoldMessenger(
      key: _messengerKey,
      child: Scaffold(
        appBar: AppBar(
          title: Text('Facility Management', style: GoogleFonts.poppins()),
          backgroundColor: Colors.grey[900],
          foregroundColor: Colors.white,
        ),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Facility Management',
                  style: GoogleFonts.poppins(fontSize: 24, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 16),
                Card(
                  elevation: 2,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Add New Facility',
                          style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: _nameController,
                          decoration: const InputDecoration(
                            labelText: 'Facility Name',
                            border: OutlineInputBorder(),
                          ),
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: _addressController,
                          decoration: const InputDecoration(
                            labelText: 'Address',
                            border: OutlineInputBorder(),
                          ),
                        ),
                        const SizedBox(height: 8),
                        ElevatedButton(
                          onPressed: _addFacility,
                          child: const Text('Add Facility'),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Facilities',
                  style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.w600),
                ),
                Expanded(
                  child: StreamBuilder<QuerySnapshot>(
                    stream: FirebaseFirestore.instance.collection('facilities').snapshots(),
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return const Center(child: CircularProgressIndicator());
                      }
                      if (snapshot.hasError) {
                        _logger.e('Firestore error: ${snapshot.error}');
                        return Center(child: Text('Error: ${snapshot.error}'));
                      }
                      if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                        _logger.w('No facilities in Firestore');
                        return const Center(child: Text('No facilities available'));
                      }

                      final facilities = snapshot.data!.docs;
                      _logger.i('Fetched ${facilities.length} facilities from Firestore');

                      return ListView.builder(
                        itemCount: facilities.length,
                        itemBuilder: (context, index) {
                          final facility = facilities[index];
                          final isSelected = facility.id == widget.facilityId;
                          return Card(
                            elevation: isSelected ? 4 : 1,
                            margin: const EdgeInsets.symmetric(vertical: 4),
                            child: ListTile(
                              title: Text(
                                facility['name'] ?? 'Unnamed Facility',
                                style: GoogleFonts.poppins(
                                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                ),
                              ),
                              subtitle: Text(facility['address'] ?? ''),
                              trailing: IconButton(
                                icon: const Icon(Icons.delete, color: Colors.red),
                                onPressed: () => _deleteFacility(facility.id),
                              ),
                              selected: isSelected,
                              onTap: () {
                                // Navigate to HomeScreen with the selected facility ID
                                Navigator.pushReplacementNamed(
                                  context,
                                  '/home',
                                  arguments: facility.id,
                                );
                              },
                            ),
                          );
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}