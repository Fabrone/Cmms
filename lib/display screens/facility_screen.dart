import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:logger/logger.dart';
import 'package:cmms/models/facility.dart';

class FacilityScreen extends StatefulWidget {
  final String? selectedFacilityId;
  final Function(String) onFacilitySelected;

  const FacilityScreen({
    super.key,
    this.selectedFacilityId,
    required this.onFacilitySelected,
  });

  @override
  State<FacilityScreen> createState() => _FacilityScreenState();
}

class _FacilityScreenState extends State<FacilityScreen> {
  final _nameController = TextEditingController();
  final _locationController = TextEditingController();
  final _addressController = TextEditingController();
  final Logger _logger = Logger();
  final GlobalKey<ScaffoldMessengerState> _messengerKey = GlobalKey<ScaffoldMessengerState>();

  Future<void> _addFacility() async {
    if (_nameController.text.isEmpty || _locationController.text.isEmpty) {
      _logger.w('Name or location empty');
      _messengerKey.currentState?.showSnackBar(
        SnackBar(
          content: Text('Please enter name and location', style: GoogleFonts.poppins()),
        ),
      );
      return;
    }

    try {
      final facility = Facility(
        id: '',
        name: _nameController.text.trim(),
        location: _locationController.text.trim(),
        address: _addressController.text.trim().isNotEmpty ? _addressController.text.trim() : null,
        createdAt: DateTime.now(),
      );

      final ref = await FirebaseFirestore.instance.collection('Facilities').add(facility.toFirestore());
      _logger.i('Facility added: ${ref.id}');
      _nameController.clear();
      _locationController.clear();
      _addressController.clear();

      if (mounted) {
        _messengerKey.currentState?.showSnackBar(
          SnackBar(content: Text('Facility added successfully', style: GoogleFonts.poppins())),
        );
        Navigator.pop(context);
      }
    } catch (e, stackTrace) {
      _logger.e('Error adding facility: $e', stackTrace: stackTrace);
      if (mounted) {
        _messengerKey.currentState?.showSnackBar(
          SnackBar(content: Text('Error adding facility: $e', style: GoogleFonts.poppins())),
        );
      }
    }
  }

  void _showAddFacilityDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Add New Facility', style: GoogleFonts.poppins(fontWeight: FontWeight.bold)),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _nameController,
                decoration: InputDecoration(
                  labelText: 'Facility Name *',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  labelStyle: GoogleFonts.poppins(),
                ),
                style: GoogleFonts.poppins(),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _locationController,
                decoration: InputDecoration(
                  labelText: 'Location *',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  labelStyle: GoogleFonts.poppins(),
                ),
                style: GoogleFonts.poppins(),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _addressController,
                decoration: InputDecoration(
                  labelText: 'Address (Optional)',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  labelStyle: GoogleFonts.poppins(),
                ),
                style: GoogleFonts.poppins(),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel', style: GoogleFonts.poppins()),
          ),
          ElevatedButton(
            onPressed: _addFacility,
            style: ElevatedButton.styleFrom(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              backgroundColor: Colors.blueGrey,
            ),
            child: Text('Add', style: GoogleFonts.poppins(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    _locationController.dispose();
    _addressController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width <= 600;

    return ScaffoldMessenger(
      key: _messengerKey,
      child: Scaffold(
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Your Facilities',
                  style: GoogleFonts.poppins(
                    fontSize: isMobile ? 20 : 24,
                    fontWeight: FontWeight.bold,
                    color: Colors.blueGrey[800],
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Select a facility to manage its maintenance tasks',
                  style: GoogleFonts.poppins(
                    fontSize: isMobile ? 14 : 16,
                    color: Colors.blueGrey[600],
                  ),
                ),
                const SizedBox(height: 16),
                Expanded(
                  child: StreamBuilder<QuerySnapshot>(
                    stream: FirebaseFirestore.instance.collection('Facilities').orderBy('createdAt', descending: true).snapshots(),
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return const Center(child: CircularProgressIndicator(color: Colors.blueGrey));
                      }
                      if (snapshot.hasError) {
                        _logger.e('Firestore error: ${snapshot.error}');
                        return Center(
                          child: Text('Error: ${snapshot.error}', style: GoogleFonts.poppins(color: Colors.red)),
                        );
                      }
                      if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                        _logger.w('No facilities in Firestore');
                        return Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.business, size: 64, color: Colors.blueGrey[300]),
                              const SizedBox(height: 16),
                              Text(
                                'No facilities added yet',
                                style: GoogleFonts.poppins(
                                  fontSize: isMobile ? 16 : 18,
                                  color: Colors.blueGrey[600],
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Click the + button to add a new facility',
                                style: GoogleFonts.poppins(
                                  fontSize: isMobile ? 14 : 16,
                                  color: Colors.blueGrey[400],
                                ),
                              ),
                            ],
                          ),
                        );
                      }

                      final facilities = snapshot.data!.docs.map((doc) => Facility.fromFirestore(doc)).toList();
                      _logger.i('Fetched ${facilities.length} facilities from Firestore');

                      return ListView.builder(
                        itemCount: facilities.length,
                        itemBuilder: (context, index) {
                          final facility = facilities[index];
                          final isSelected = facility.id == widget.selectedFacilityId;

                          return GestureDetector(
                            onTap: () {
                              widget.onFacilitySelected(facility.id);
                            },
                            child: Card(
                              elevation: isSelected ? 6 : 2,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              color: isSelected ? Colors.blueGrey[50] : Colors.white,
                              margin: const EdgeInsets.symmetric(vertical: 8),
                              child: Padding(
                                padding: const EdgeInsets.all(16.0),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      facility.name,
                                      style: GoogleFonts.poppins(
                                        fontSize: isMobile ? 16 : 18,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.blueGrey[800],
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      facility.location,
                                      style: GoogleFonts.poppins(
                                        fontSize: isMobile ? 14 : 16,
                                        color: Colors.blueGrey[600],
                                      ),
                                    ),
                                    if (facility.address != null) ...[
                                      const SizedBox(height: 4),
                                      Text(
                                        facility.address!,
                                        style: GoogleFonts.poppins(
                                          fontSize: isMobile ? 12 : 14,
                                          color: Colors.blueGrey[500],
                                        ),
                                      ),
                                    ],
                                    const SizedBox(height: 4),
                                    Text(
                                      'Added: ${facility.createdAt.toLocal().toString().split(' ')[0]}',
                                      style: GoogleFonts.poppins(
                                        fontSize: isMobile ? 12 : 14,
                                        color: Colors.blueGrey[400],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
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
        floatingActionButton: FloatingActionButton.extended(
          onPressed: _showAddFacilityDialog,
          backgroundColor: Colors.blueGrey,
          icon: const Icon(Icons.add, color: Colors.white),
          label: Text(
            'Add Facility',
            style: GoogleFonts.poppins(color: Colors.white, fontWeight: FontWeight.w600),
          ),
          elevation: 8,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
    );
  }
}