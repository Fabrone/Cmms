import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:logger/logger.dart';
import 'package:cmms/models/facility.dart';

class FacilityScreen extends StatefulWidget {
  final String? selectedFacilityId;
  final void Function(String) onFacilitySelected;

  const FacilityScreen({
    super.key,
    required this.selectedFacilityId,
    required this.onFacilitySelected,
  });

  @override
  FacilityScreenState createState() => FacilityScreenState();
}

class FacilityScreenState extends State<FacilityScreen> {
  final Logger logger = Logger(printer: PrettyPrinter());
  final GlobalKey<ScaffoldMessengerState> _messengerKey = GlobalKey<ScaffoldMessengerState>();
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _locationController = TextEditingController();
  final TextEditingController _addressController = TextEditingController();
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  bool _isAddingFacility = false;

  @override
  void dispose() {
    _nameController.dispose();
    _locationController.dispose();
    _addressController.dispose();
    super.dispose();
  }

  Future<void> _addFacility() async {
    if (_formKey.currentState!.validate()) {
      try {
        final user = FirebaseAuth.instance.currentUser;
        if (user == null) {
          _messengerKey.currentState?.showSnackBar(
            SnackBar(content: Text('Please log in to add a facility', style: GoogleFonts.poppins())),
          );
          return;
        }
        final facility = Facility(
          id: '',
          name: _nameController.text.trim(),
          location: _locationController.text.trim(),
          address: _addressController.text.trim().isNotEmpty ? _addressController.text.trim() : null,
          createdAt: DateTime.now(),
          createdBy: user.uid,
        );

        final ref = await FirebaseFirestore.instance.collection('Facilities').add(facility.toFirestore());
        widget.onFacilitySelected(ref.id);
        _nameController.clear();
        _locationController.clear();
        _addressController.clear();
        setState(() {
          _isAddingFacility = false;
        });
        logger.i('Facility added: ${ref.id}');
        if (mounted) {
          _messengerKey.currentState?.showSnackBar(
            SnackBar(content: Text('Facility added successfully', style: GoogleFonts.poppins())),
          );
        }
      } catch (e) {
        logger.e('Error adding facility: $e');
        if (mounted) {
          _messengerKey.currentState?.showSnackBar(
            SnackBar(content: Text('Error adding facility: $e', style: GoogleFonts.poppins())),
          );
        }
      }
    }
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
                        logger.e('Firestore error: ${snapshot.error}');
                        return Center(
                          child: Text('Error: ${snapshot.error}', style: GoogleFonts.poppins(color: Colors.red)),
                        );
                      }
                      final docs = snapshot.data?.docs ?? [];
                      if (docs.isEmpty && !_isAddingFacility) {
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
                      if (_isAddingFacility) {
                        return Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: Form(
                            key: _formKey,
                            child: Column(
                              children: [
                                TextFormField(
                                  controller: _nameController,
                                  decoration: InputDecoration(
                                    labelText: 'Facility Name *',
                                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                                    labelStyle: GoogleFonts.poppins(),
                                  ),
                                  style: GoogleFonts.poppins(),
                                  validator: (value) => value!.isEmpty ? 'Enter facility name' : null,
                                ),
                                const SizedBox(height: 12),
                                TextFormField(
                                  controller: _locationController,
                                  decoration: InputDecoration(
                                    labelText: 'Location (optional)',
                                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                                    labelStyle: GoogleFonts.poppins(),
                                  ),
                                  style: GoogleFonts.poppins(),
                                ),
                                const SizedBox(height: 12),
                                TextFormField(
                                  controller: _addressController,
                                  decoration: InputDecoration(
                                    labelText: 'Address (optional)',
                                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                                    labelStyle: GoogleFonts.poppins(),
                                  ),
                                  style: GoogleFonts.poppins(),
                                ),
                                const SizedBox(height: 16),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.end,
                                  children: [
                                    TextButton(
                                      onPressed: () {
                                        setState(() {
                                          _isAddingFacility = false;
                                        });
                                        _nameController.clear();
                                        _locationController.clear();
                                        _addressController.clear();
                                      },
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
                              ],
                            ),
                          ),
                        );
                      }
                      final facilities = docs.map((doc) => Facility.fromFirestore(doc)).toList();
                      logger.i('Fetched ${facilities.length} facilities from Firestore');

                      return ListView.builder(
                        itemCount: facilities.length,
                        itemBuilder: (context, index) {
                          final facility = facilities[index];
                          final isSelected = facility.id == widget.selectedFacilityId;
                          return GestureDetector(
                            onTap: () {
                              widget.onFacilitySelected(facility.id);
                              logger.i('Selected facility: ${facility.name}, ID: ${facility.id}');
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
          onPressed: () {
            setState(() {
              _isAddingFacility = true;
            });
          },
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