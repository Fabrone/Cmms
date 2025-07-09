import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:logger/logger.dart';
import 'package:cmms/models/facility.dart';

class FacilityScreen extends StatefulWidget {
  final String? selectedFacilityId;
  final void Function(String) onFacilitySelected;
  final bool isSelectionActive;
  final String? userOrganization; // User's organization for filtering
  final bool isServiceProvider; // Whether user is a service provider

  const FacilityScreen({
    super.key,
    required this.selectedFacilityId,
    required this.onFacilitySelected,
    required this.isSelectionActive,
    this.userOrganization,
    this.isServiceProvider = false,
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
  final ScrollController _scrollController = ScrollController();
  bool _isAddingFacility = false;

  @override
  void dispose() {
    _nameController.dispose();
    _locationController.dispose();
    _addressController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  // Get user's organization for facility creation
  Future<String> _getUserOrganization() async {
    if (widget.userOrganization != null && widget.userOrganization!.isNotEmpty && widget.userOrganization != '-') {
      return widget.userOrganization!;
    }

    // Fallback: get organization from user data
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return 'Embassy'; // Default fallback

    try {
      // Check Technicians collection first
      final technicianDoc = await FirebaseFirestore.instance
          .collection('Technicians')
          .doc(user.uid)
          .get();

      if (technicianDoc.exists) {
        return technicianDoc.data()?['organization'] ?? 'Embassy';
      }

      // Check Users collection
      final userDoc = await FirebaseFirestore.instance
          .collection('Users')
          .doc(user.uid)
          .get();

      if (userDoc.exists) {
        return userDoc.data()?['organization'] ?? 'Embassy';
      }
    } catch (e) {
      logger.e('Error getting user organization: $e');
    }

    return 'Embassy'; // Default fallback
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

        // Get organization for the facility
        final organizationForFacility = await _getUserOrganization();
        logger.i('Creating facility with organization: $organizationForFacility');

        final facility = Facility(
          id: '',
          name: _nameController.text.trim(),
          location: _locationController.text.trim(),
          address: _addressController.text.trim().isNotEmpty ? _addressController.text.trim() : null,
          organization: organizationForFacility, // Include organization
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
        logger.i('Facility added: ${ref.id} with organization: $organizationForFacility');
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

  void _cancelAddingFacility() {
    setState(() {
      _isAddingFacility = false;
    });
    _nameController.clear();
    _locationController.clear();
    _addressController.clear();
  }

  // Build query based on user type and organization
  Stream<QuerySnapshot<Map<String, dynamic>>> _buildFacilitiesStream() {
    Query<Map<String, dynamic>> query = FirebaseFirestore.instance.collection('Facilities');

    // Filter by organization if user is not a service provider or if specific organization is selected
    if (widget.userOrganization != null && widget.userOrganization!.isNotEmpty && widget.userOrganization != '-') {
      query = query.where('organization', isEqualTo: widget.userOrganization);
      logger.i('Filtering facilities by organization: ${widget.userOrganization}');
    }

    // Order by createdAt descending
    query = query.orderBy('createdAt', descending: true);

    return query.snapshots();
  }

  Widget _buildFacilitiesList() {
    return StreamBuilder<QuerySnapshot>(
      stream: _buildFacilitiesStream(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
            child: CircularProgressIndicator(color: Colors.blueGrey),
          );
        }
        
        if (snapshot.hasError) {
          logger.e('Firestore error: ${snapshot.error}');
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.error, size: 64, color: Colors.red[400]),
                const SizedBox(height: 16),
                Text(
                  'Error loading facilities',
                  style: GoogleFonts.poppins(
                    fontSize: 18,
                    color: Colors.red[600],
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '${snapshot.error}',
                  style: GoogleFonts.poppins(
                    color: Colors.grey[600],
                    fontSize: 14,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          );
        }
        
        final docs = snapshot.data?.docs ?? [];
        
        // Show empty state when no facilities
        if (docs.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.business,
                  size: 64,
                  color: Colors.blueGrey[300],
                ),
                const SizedBox(height: 16),
                Text(
                  widget.userOrganization != null && widget.userOrganization!.isNotEmpty && widget.userOrganization != '-'
                      ? 'No facilities found for ${widget.userOrganization}'
                      : 'No facilities added yet',
                  style: GoogleFonts.poppins(
                    fontSize: 18,
                    color: Colors.blueGrey[600],
                    fontWeight: FontWeight.w500,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  'Click the + button to add a new facility',
                  style: GoogleFonts.poppins(
                    fontSize: 14,
                    color: Colors.blueGrey[400],
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          );
        }
        
        // Show facilities list
        final facilities = docs.map((doc) => Facility.fromFirestore(doc)).toList();
        logger.i('Fetched ${facilities.length} facilities from Firestore for organization: ${widget.userOrganization ?? 'all'}');

        return ListView.builder(
          padding: const EdgeInsets.only(bottom: 80), // Space for FAB
          itemCount: facilities.length,
          itemBuilder: (context, index) {
            final facility = facilities[index];
            final isSelected = facility.id == widget.selectedFacilityId;
            final isInteractable = widget.isSelectionActive || isSelected;

            return GestureDetector(
              onTap: isInteractable
                  ? () {
                      widget.onFacilitySelected(facility.id);
                      logger.i(
                        'Selected facility: ${facility.name}, ID: ${facility.id}, Organization: ${facility.organization}',
                      );
                    }
                  : null,
              child: Card(
                elevation: isSelected ? 6 : 2,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                color: isSelected
                    ? Colors.blueGrey[800]
                    : isInteractable
                        ? Colors.white
                        : Colors.grey[200],
                margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              facility.name,
                              style: GoogleFonts.poppins(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: isSelected
                                    ? Colors.white
                                    : isInteractable
                                        ? Colors.blueGrey[800]
                                        : Colors.grey[600],
                              ),
                            ),
                          ),
                          // Show organization badge
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: isSelected 
                                  ? Colors.white.withValues(alpha: 0.2)
                                  : Colors.blueGrey[100],
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              facility.organization,
                              style: GoogleFonts.poppins(
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                                color: isSelected
                                    ? Colors.white.withValues(alpha: 0.9)
                                    : Colors.blueGrey[700],
                              ),
                            ),
                          ),
                        ],
                      ),
                      if (facility.location.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Icon(
                              Icons.location_on,
                              size: 16,
                              color: isSelected
                                  ? Colors.white.withValues(alpha: 0.8)
                                  : Colors.blueGrey[500],
                            ),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                facility.location,
                                style: GoogleFonts.poppins(
                                  fontSize: 14,
                                  color: isSelected
                                      ? Colors.white.withValues(alpha: 0.9)
                                      : isInteractable
                                          ? Colors.blueGrey[600]
                                          : Colors.grey[500],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                      if (facility.address != null && facility.address!.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Icon(
                              Icons.home,
                              size: 16,
                              color: isSelected
                                  ? Colors.white.withValues(alpha: 0.8)
                                  : Colors.blueGrey[500],
                            ),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                facility.address!,
                                style: GoogleFonts.poppins(
                                  fontSize: 12,
                                  color: isSelected
                                      ? Colors.white.withValues(alpha: 0.8)
                                      : isInteractable
                                          ? Colors.blueGrey[500]
                                          : Colors.grey[400],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                      const SizedBox(height: 8),
                      Text(
                        'Added: ${facility.createdAt.toLocal().toString().split(' ')[0]}',
                        style: GoogleFonts.poppins(
                          fontSize: 12,
                          color: isSelected
                              ? Colors.white.withValues(alpha: 0.7)
                              : isInteractable
                                  ? Colors.blueGrey[400]
                                  : Colors.grey[400],
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
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isMobile = screenWidth <= 600;
    final isDesktop = screenWidth > 1200;
    
    // Calculate content width - 60% for desktop, full width for mobile/tablet
    final contentWidth = isDesktop ? screenWidth * 0.6 : screenWidth;

    return ScaffoldMessenger(
      key: _messengerKey,
      child: Scaffold(
        body: SafeArea(
          child: Center(
            child: SizedBox(
              width: contentWidth,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Header section (only show when not adding facility)
                  if (!_isAddingFacility) ...[
                    Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.isServiceProvider && widget.userOrganization != null 
                                ? '${widget.userOrganization} Facilities'
                                : 'Your Facilities',
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
                          // Show organization info if applicable
                          if (widget.userOrganization != null && widget.userOrganization!.isNotEmpty && widget.userOrganization != '-') ...[
                            const SizedBox(height: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: Colors.blueGrey[100],
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                'Organization: ${widget.userOrganization}',
                                style: GoogleFonts.poppins(
                                  fontSize: isMobile ? 12 : 14,
                                  color: Colors.blueGrey[700],
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                  
                  // Main content area
                  Expanded(
                    child: _isAddingFacility 
                        ? _AddFacilityFormWidget(
                            formKey: _formKey,
                            nameController: _nameController,
                            locationController: _locationController,
                            addressController: _addressController,
                            userOrganization: widget.userOrganization,
                            onCancel: _cancelAddingFacility,
                            onAdd: _addFacility,
                          )
                        : Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16.0),
                            child: _buildFacilitiesList(),
                          ),
                  ),
                ],
              ),
            ),
          ),
        ),
        floatingActionButton: _isAddingFacility 
            ? null // Hide FAB when adding facility to prevent overlap
            : FloatingActionButton.extended(
                onPressed: () {
                  setState(() {
                    _isAddingFacility = true;
                  });
                },
                backgroundColor: Colors.blueGrey,
                icon: const Icon(Icons.add, color: Colors.white),
                label: Text(
                  'Add Facility',
                  style: GoogleFonts.poppins(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                elevation: 8,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
      ),
    );
  }
}

class _AddFacilityFormWidget extends StatelessWidget {
  final GlobalKey<FormState> formKey;
  final TextEditingController nameController;
  final TextEditingController locationController;
  final TextEditingController addressController;
  final String? userOrganization;
  final VoidCallback onCancel;
  final VoidCallback onAdd;

  const _AddFacilityFormWidget({
    required this.formKey,
    required this.nameController,
    required this.locationController,
    required this.addressController,
    required this.userOrganization,
    required this.onCancel,
    required this.onAdd,
  });

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;
    final keyboardHeight = MediaQuery.of(context).viewInsets.bottom;
    final availableHeight = screenHeight - keyboardHeight - kToolbarHeight - MediaQuery.of(context).padding.top - MediaQuery.of(context).padding.bottom;
    
    return SizedBox(
      height: availableHeight,
      child: SingleChildScrollView(
        padding: const EdgeInsets.only(
          left: 16.0,
          right: 16.0,
          top: 16.0,
          bottom: 100.0, // Extra padding to ensure buttons are visible above FAB
        ),
        child: Form(
          key: formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                children: [
                  IconButton(
                    onPressed: onCancel,
                    icon: const Icon(Icons.arrow_back),
                    color: Colors.blueGrey[700],
                  ),
                  Text(
                    'Add New Facility',
                    style: GoogleFonts.poppins(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Colors.blueGrey[800],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              
              // Show organization info in form
              if (userOrganization != null && userOrganization!.isNotEmpty && userOrganization != '-') ...[
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.blueGrey[50],
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.blueGrey[200]!),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Organization',
                        style: GoogleFonts.poppins(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: Colors.blueGrey[700],
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        userOrganization!,
                        style: GoogleFonts.poppins(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.blueGrey[800],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
              ],
              
              // Form fields
              TextFormField(
                controller: nameController,
                decoration: InputDecoration(
                  labelText: 'Facility Name *',
                  hintText: 'Enter facility name',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  labelStyle: GoogleFonts.poppins(),
                  prefixIcon: const Icon(Icons.business),
                ),
                style: GoogleFonts.poppins(),
                validator: (value) => value!.isEmpty ? 'Enter facility name' : null,
                textInputAction: TextInputAction.next,
              ),
              const SizedBox(height: 16),
              
              TextFormField(
                controller: locationController,
                decoration: InputDecoration(
                  labelText: 'Location',
                  hintText: 'Enter location (optional)',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  labelStyle: GoogleFonts.poppins(),
                  prefixIcon: const Icon(Icons.location_on),
                ),
                style: GoogleFonts.poppins(),
                textInputAction: TextInputAction.next,
              ),
              const SizedBox(height: 16),
              
              TextFormField(
                controller: addressController,
                decoration: InputDecoration(
                  labelText: 'Address',
                  hintText: 'Enter full address (optional)',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  labelStyle: GoogleFonts.poppins(),
                  prefixIcon: const Icon(Icons.home),
                ),
                style: GoogleFonts.poppins(),
                maxLines: 2,
                textInputAction: TextInputAction.done,
              ),
              const SizedBox(height: 32),
              
              // Action buttons
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: onCancel,
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        side: BorderSide(color: Colors.blueGrey[300]!),
                      ),
                      child: Text(
                        'Cancel',
                        style: GoogleFonts.poppins(
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                          color: Colors.blueGrey[700],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: onAdd,
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        backgroundColor: Colors.blueGrey,
                        foregroundColor: Colors.white,
                      ),
                      child: Text(
                        'Add Facility',
                        style: GoogleFonts.poppins(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 32), // Extra space at bottom
            ],
          ),
        ),
      ),
    );
  }
}