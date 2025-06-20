import 'package:cmms/display%20screens/google_maps_screen.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:logger/logger.dart';
import 'package:cmms/models/facility.dart';
import 'package:cmms/widgets/responsive_screen_wrapper.dart';

class LocationsScreen extends StatefulWidget {
  final String facilityId;

  const LocationsScreen({super.key, required this.facilityId});

  @override
  State<LocationsScreen> createState() => _LocationsScreenState();
}

class _LocationsScreenState extends State<LocationsScreen> {
  final Logger _logger = Logger(printer: PrettyPrinter());

  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _locationController = TextEditingController();
  final TextEditingController _addressController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _logger.i('Initializing LocationsScreen, facilityId: ${widget.facilityId}, user: ${FirebaseAuth.instance.currentUser?.uid}');
  }

  @override
  void dispose() {
    _nameController.dispose();
    _locationController.dispose();
    _addressController.dispose();
    super.dispose();
    _logger.i('Disposed LocationsScreen');
  }

  /// Adds a new facility to Firestore.
  Future<void> _addFacility() async {
    if (_nameController.text.trim().isEmpty || _locationController.text.trim().isEmpty) {
      _showSnackBar('Please fill in all required fields');
      return;
    }

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        _showSnackBar('User not authenticated');
        _logger.w('User not authenticated for adding facility');
        return;
      }

      final facility = Facility(
        id: '',
        name: _nameController.text.trim(),
        location: _locationController.text.trim(),
        address: _addressController.text.trim().isEmpty ? null : _addressController.text.trim(),
        createdAt: DateTime.now(),
        createdBy: user.uid,
      );

      await FirebaseFirestore.instance
          .collection('Facilities')
          .add(facility.toFirestore());

      if (!mounted) return;

      _showSnackBar('Facility added successfully');
      _logger.i('Facility added: ${facility.name}, facilityId: ${widget.facilityId}');
      _clearForm();
      Navigator.pop(context);
    } catch (e, stackTrace) {
      _logger.e('Error adding facility: $e', stackTrace: stackTrace);
      _showSnackBar('Error adding facility: $e');
    }
  }

  /// Clears the form fields.
  void _clearForm() {
    _nameController.clear();
    _locationController.clear();
    _addressController.clear();
  }

  /// Shows a snackbar with the given message.
  void _showSnackBar(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message, style: GoogleFonts.poppins())),
      );
    }
  }

  /// Displays a dialog for adding a new facility.
  void _showAddFacilityDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          'Add New Facility',
          style: GoogleFonts.poppins(
            fontWeight: FontWeight.bold,
            color: Colors.blueGrey[800],
          ),
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _nameController,
                decoration: InputDecoration(
                  labelText: 'Facility Name *',
                  border: const OutlineInputBorder(),
                  labelStyle: GoogleFonts.poppins(),
                ),
                style: GoogleFonts.poppins(),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _locationController,
                decoration: InputDecoration(
                  labelText: 'Location *',
                  hintText: 'e.g., Nairobi, Mombasa, Kisumu',
                  border: const OutlineInputBorder(),
                  labelStyle: GoogleFonts.poppins(),
                ),
                style: GoogleFonts.poppins(),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _addressController,
                decoration: InputDecoration(
                  labelText: 'Address (Optional)',
                  border: const OutlineInputBorder(),
                  labelStyle: GoogleFonts.poppins(),
                ),
                style: GoogleFonts.poppins(),
                maxLines: 2,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              _clearForm();
              Navigator.pop(context);
            },
            child: Text('Cancel', style: GoogleFonts.poppins()),
          ),
          ElevatedButton(
            onPressed: _addFacility,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blueGrey,
              foregroundColor: Colors.white,
            ),
            child: Text('Add Facility', style: GoogleFonts.poppins()),
          ),
        ],
      ),
    );
  }

  /// Shows a dialog with facility details.
  void _showFacilityDetails(Facility facility) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          facility.name,
          style: GoogleFonts.poppins(
            fontWeight: FontWeight.bold,
            color: Colors.blueGrey[800],
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildDetailRow(Icons.location_on, 'Location', facility.location),
            if (facility.address != null) ...[
              const SizedBox(height: 12),
              _buildDetailRow(Icons.home, 'Address', facility.address!),
            ],
            const SizedBox(height: 12),
            _buildDetailRow(
              Icons.calendar_today,
              'Created',
              '${facility.createdAt.day}/${facility.createdAt.month}/${facility.createdAt.year}',
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Close', style: GoogleFonts.poppins()),
          ),
          ElevatedButton.icon(
            onPressed: () {
              Navigator.pop(context);
              _openGoogleMaps(facility.name, facility.location);
            },
            icon: const Icon(Icons.map),
            label: Text('View on Map', style: GoogleFonts.poppins()),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green,
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  /// Builds a row for displaying facility details.
  Widget _buildDetailRow(IconData icon, String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: Colors.blueGrey[700], size: 20),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: GoogleFonts.poppins(
                  fontSize: 12,
                  color: Colors.grey[600],
                  fontWeight: FontWeight.w500,
                ),
              ),
              Text(
                value,
                style: GoogleFonts.poppins(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// Opens Google Maps screen for the given facility.
  void _openGoogleMaps(String facilityName, String location) async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => GoogleMapsScreen(
          facilityName: facilityName,
          initialLocation: location,
        ),
      ),
    );

    if (result != null && mounted) {
      _showSnackBar('Map configuration updated for $facilityName');
      _logger.i('Map updated for $facilityName');
    }
  }

  @override
  Widget build(BuildContext context) {
    _logger.d('Building LocationsScreen, facilityId: ${widget.facilityId}');
    return ResponsiveScreenWrapper(
      title: 'Locations',
      facilityId: widget.facilityId,
      floatingActionButton: FloatingActionButton(
        onPressed: _showAddFacilityDialog,
        backgroundColor: Colors.blueGrey,
        child: const Icon(Icons.add, color: Colors.white),
      ),
      child: _buildBody(),
    );
  }

  /// Builds the main content of the screen.
  Widget _buildBody() {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Facilities',
            style: GoogleFonts.poppins(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: Colors.blueGrey[800],
            ),
          ),
          const SizedBox(height: 16),
          Expanded(child: _buildFacilitiesList()),
        ],
      ),
    );
  }

  /// Builds the list of facilities using StreamBuilder.
  Widget _buildFacilitiesList() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('Facilities')
          .orderBy('createdAt', descending: true)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (snapshot.hasError) {
          _logger.e('Error loading facilities: ${snapshot.error}');
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
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Error: ${snapshot.error}',
                  style: GoogleFonts.poppins(
                    color: Colors.grey[500],
                    fontSize: 12,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          );
        }

        final facilities = snapshot.data?.docs ?? [];

        if (facilities.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.location_city,
                  size: 64,
                  color: Colors.grey[400],
                ),
                const SizedBox(height: 16),
                Text(
                  'No facilities found',
                  style: GoogleFonts.poppins(
                    fontSize: 18,
                    color: Colors.grey[600],
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Tap the + button to add your first facility',
                  style: GoogleFonts.poppins(
                    color: Colors.grey[500],
                  ),
                ),
              ],
            ),
          );
        }

        return ListView.builder(
          itemCount: facilities.length,
          itemBuilder: (context, index) {
            final facility = Facility.fromFirestore(facilities[index]);
            return _buildFacilityTile(facility);
          },
        );
      },
    );
  }

  /// Builds a tile for a single facility.
  Widget _buildFacilityTile(Facility facility) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 2,
      child: ListTile(
        contentPadding: const EdgeInsets.all(16),
        leading: CircleAvatar(
          radius: 25,
          backgroundColor: Colors.blueGrey[100],
          child: Icon(
            Icons.location_city,
            color: Colors.blueGrey[700],
            size: 28,
          ),
        ),
        title: Text(
          facility.name,
          style: GoogleFonts.poppins(
            fontWeight: FontWeight.bold,
            fontSize: 16,
          ),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            Row(
              children: [
                Icon(Icons.place, size: 16, color: Colors.grey[600]),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    facility.location,
                    style: GoogleFonts.poppins(fontSize: 14),
                  ),
                ),
              ],
            ),
            if (facility.address != null) ...[
              const SizedBox(height: 4),
              Row(
                children: [
                  Icon(Icons.home, size: 16, color: Colors.grey[600]),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      facility.address!,
                      style: GoogleFonts.poppins(
                        fontSize: 12,
                        color: Colors.grey[600],
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              onPressed: () => _openGoogleMaps(facility.name, facility.location),
              icon: const Icon(Icons.map),
              tooltip: 'View on Map',
              color: Colors.green[700],
            ),
            const Icon(Icons.arrow_forward_ios, size: 16),
          ],
        ),
        onTap: () => _showFacilityDetails(facility),
      ),
    );
  }
}