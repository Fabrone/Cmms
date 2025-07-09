import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:logger/logger.dart';
import 'package:geolocator/geolocator.dart';
import 'package:url_launcher/url_launcher.dart';
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
  String? _userOrganization;
  bool _isDeveloper = false;
  bool _isJVAlmacisUser = false;

  @override
  void initState() {
    super.initState();
    _initializeUserData();
  }

  /// Initialize user data and organization
  Future<void> _initializeUserData() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      // Check if user is developer
      final developerDoc = await FirebaseFirestore.instance
          .collection('Developers')
          .doc(user.uid)
          .get();
      
      if (developerDoc.exists) {
        setState(() {
          _isDeveloper = true;
        });
        _logger.i('User is developer');
        return;
      }

      // Get user organization
      final userDoc = await FirebaseFirestore.instance
          .collection('Users')
          .doc(user.uid)
          .get();

      if (userDoc.exists) {
        final organization = userDoc.data()?['organization'] as String?;
        setState(() {
          _userOrganization = organization;
          _isJVAlmacisUser = organization == 'JV Almacis';
        });
        _logger.i('User organization: $organization, isJVAlmacis: $_isJVAlmacisUser');
      }
    } catch (e) {
      _logger.e('Error initializing user data: $e');
    }
  }

  /// Shows a snackbar with the given message
  void _showSnackBar(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message, style: GoogleFonts.poppins())),
      );
    }
  }

  /// Opens Google Maps with directions from current location to facility
  Future<void> _openDirections(String facilityName, String facilityLocation) async {
    try {
      // Request location permission
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          _showSnackBar('Location permission denied');
          return;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        _showSnackBar('Location permissions are permanently denied');
        return;
      }

      // Get current position with updated LocationSettings
      final Position position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 10,
        ),
      );

      // Create Google Maps directions URL
      final String googleMapsUrl = 
          'https://www.google.com/maps/dir/${position.latitude},${position.longitude}/$facilityLocation';

      final Uri url = Uri.parse(googleMapsUrl);
      
      if (await canLaunchUrl(url)) {
        await launchUrl(url, mode: LaunchMode.externalApplication);
        _logger.i('Opened directions to $facilityName at $facilityLocation');
      } else {
        _showSnackBar('Could not open Google Maps');
      }
    } catch (e) {
      _logger.e('Error opening directions: $e');
      _showSnackBar('Error getting directions: $e');
    }
  }

  /// Opens Google Maps showing facility location
  Future<void> _openLocation(String facilityName, String facilityLocation) async {
    try {
      // Create Google Maps location URL
      final String googleMapsUrl = 
          'https://www.google.com/maps/search/?api=1&query=$facilityLocation';

      final Uri url = Uri.parse(googleMapsUrl);
      
      if (await canLaunchUrl(url)) {
        await launchUrl(url, mode: LaunchMode.externalApplication);
        _logger.i('Opened location for $facilityName at $facilityLocation');
      } else {
        _showSnackBar('Could not open Google Maps');
      }
    } catch (e) {
      _logger.e('Error opening location: $e');
      _showSnackBar('Error opening location: $e');
    }
  }

  /// Shows facility location options dialog
  void _showLocationOptions(Facility facility) {
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
            Row(
              children: [
                Icon(Icons.location_on, color: Colors.blueGrey[700], size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    facility.location,
                    style: GoogleFonts.poppins(fontSize: 16),
                  ),
                ),
              ],
            ),
            if (facility.address != null) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(Icons.home, color: Colors.blueGrey[700], size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      facility.address!,
                      style: GoogleFonts.poppins(
                        fontSize: 14,
                        color: Colors.grey[600],
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel', style: GoogleFonts.poppins()),
          ),
          ElevatedButton.icon(
            onPressed: () {
              Navigator.pop(context);
              _openLocation(facility.name, facility.location);
            },
            icon: const Icon(Icons.place),
            label: Text('Location', style: GoogleFonts.poppins()),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blue,
              foregroundColor: Colors.white,
            ),
          ),
          ElevatedButton.icon(
            onPressed: () {
              Navigator.pop(context);
              _openDirections(facility.name, facility.location);
            },
            icon: const Icon(Icons.directions),
            label: Text('Directions', style: GoogleFonts.poppins()),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green,
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ResponsiveScreenWrapper(
      title: 'Locations',
      facilityId: widget.facilityId,
      child: _buildBody(),
    );
  }

  /// Builds the main content of the screen
  Widget _buildBody() {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Facility Locations',
            style: GoogleFonts.poppins(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: Colors.blueGrey[800],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'View facility locations and get directions',
            style: GoogleFonts.poppins(
              fontSize: 14,
              color: Colors.grey[600],
            ),
          ),
          const SizedBox(height: 16),
          Expanded(child: _buildFacilitiesList()),
        ],
      ),
    );
  }

  /// Builds the list of facilities with organization-based filtering
  Widget _buildFacilitiesList() {
    // Build query based on user type
    Query<Map<String, dynamic>> query = FirebaseFirestore.instance
        .collection('Facilities')
        .orderBy('createdAt', descending: true);

    // Apply organization filter for non-developer, non-JV Almacis users
    if (!_isDeveloper && !_isJVAlmacisUser && _userOrganization != null) {
      query = query.where('organization', isEqualTo: _userOrganization);
    }

    return StreamBuilder<QuerySnapshot>(
      stream: query.snapshots(),
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
                  'Please check your permissions and try again',
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
                  _isDeveloper || _isJVAlmacisUser
                      ? 'No facilities have been added yet'
                      : 'No facilities found for your organization',
                  style: GoogleFonts.poppins(
                    color: Colors.grey[500],
                  ),
                  textAlign: TextAlign.center,
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

  /// Builds a tile for a single facility
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
            if (_isDeveloper || _isJVAlmacisUser) ...[
              const SizedBox(height: 4),
              Row(
                children: [
                  Icon(Icons.business, size: 16, color: Colors.grey[600]),
                  const SizedBox(width: 4),
                  Text(
                    facility.organization,
                    style: GoogleFonts.poppins(
                      fontSize: 12,
                      color: Colors.grey[600],
                      fontWeight: FontWeight.w500,
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
              onPressed: () => _openDirections(facility.name, facility.location),
              icon: const Icon(Icons.directions),
              tooltip: 'Get Directions',
              color: Colors.green[700],
            ),
            IconButton(
              onPressed: () => _openLocation(facility.name, facility.location),
              icon: const Icon(Icons.place),
              tooltip: 'View Location',
              color: Colors.blue[700],
            ),
          ],
        ),
        onTap: () => _showLocationOptions(facility),
      ),
    );
  }
}