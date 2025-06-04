import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:logger/logger.dart';
import 'package:cmms/models/facility.dart';

class LocationsScreen extends StatefulWidget {
  final String facilityId;

  const LocationsScreen({super.key, required this.facilityId});

  @override
  State<LocationsScreen> createState() => _LocationsScreenState();
}

class _LocationsScreenState extends State<LocationsScreen> {
  final Logger _logger = Logger();
  final GlobalKey<ScaffoldMessengerState> _messengerKey = GlobalKey<ScaffoldMessengerState>();
  bool _isLoading = true;
  List<Facility> _facilities = [];
  Facility? _selectedFacility;

  @override
  void initState() {
    super.initState();
    _logger.i('LocationsScreen initialized: facilityId=${widget.facilityId}');
    _loadFacilities();
  }

  Future<void> _loadFacilities() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('Facilities')
          .orderBy('createdAt', descending: true)
          .get();

      final facilities = snapshot.docs.map((doc) => Facility.fromFirestore(doc)).toList();
      
      if (mounted) {
        setState(() {
          _facilities = facilities;
          _isLoading = false;
          
          // Set the selected facility based on the provided facilityId
          if (widget.facilityId.isNotEmpty) {
            _selectedFacility = _facilities.firstWhere(
              (facility) => facility.id == widget.facilityId,
              orElse: () => _facilities.first,
            );
          } else if (_facilities.isNotEmpty) {
            _selectedFacility = _facilities.first;
          }
        });
      }
      
      _logger.i('Loaded ${facilities.length} facilities');
    } catch (e) {
      _logger.e('Error loading facilities: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
        _messengerKey.currentState?.showSnackBar(
          SnackBar(content: Text('Error loading facilities: $e', style: GoogleFonts.poppins())),
        );
      }
    }
  }

  void _showMapView(Facility facility) {
    // This will be implemented later as mentioned by the user
    _messengerKey.currentState?.showSnackBar(
      SnackBar(
        content: Text(
          'Map view for ${facility.name} will be implemented in the future.',
          style: GoogleFonts.poppins(),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isMobile = screenWidth <= 600;

    return ScaffoldMessenger(
      key: _messengerKey,
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            'Facility Locations',
            style: GoogleFonts.poppins(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: isMobile ? 20 : 24,
            ),
          ),
          backgroundColor: Colors.blueGrey[800],
          leading: IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.white),
            onPressed: () => Navigator.pop(context),
          ),
          elevation: 0,
        ),
        body: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : _buildContent(isMobile),
      ),
    );
  }

  Widget _buildContent(bool isMobile) {
    if (_facilities.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.location_off, size: 64, color: Colors.grey[400]),
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
              'Add facilities to view their locations',
              style: GoogleFonts.poppins(
                fontSize: 14,
                color: Colors.grey[500],
              ),
            ),
          ],
        ),
      );
    }

    if (isMobile) {
      return _buildMobileLayout();
    } else {
      return _buildTabletWebLayout();
    }
  }

  Widget _buildMobileLayout() {
    return Column(
      children: [
        // Facility selector
        Container(
          padding: const EdgeInsets.all(16),
          color: Colors.grey[100],
          child: DropdownButtonFormField<String>(
            value: _selectedFacility?.id,
            items: _facilities
                .map((facility) => DropdownMenuItem(
                      value: facility.id,
                      child: Text(facility.name, style: GoogleFonts.poppins()),
                    ))
                .toList(),
            onChanged: (value) {
              if (value != null) {
                setState(() {
                  _selectedFacility = _facilities.firstWhere((f) => f.id == value);
                });
              }
            },
            decoration: InputDecoration(
              labelText: 'Select Facility',
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              filled: true,
              fillColor: Colors.white,
              labelStyle: GoogleFonts.poppins(),
            ),
          ),
        ),
        
        // Selected facility details
        if (_selectedFacility != null) Expanded(child: _buildFacilityDetails(_selectedFacility!)),
      ],
    );
  }

  Widget _buildTabletWebLayout() {
    return Row(
      children: [
        // Facility list (left sidebar)
        Container(
          width: 250,
          color: Colors.grey[100],
          child: ListView.builder(
            itemCount: _facilities.length,
            itemBuilder: (context, index) {
              final facility = _facilities[index];
              final isSelected = _selectedFacility?.id == facility.id;
              
              return ListTile(
                title: Text(
                  facility.name,
                  style: GoogleFonts.poppins(
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                  ),
                ),
                subtitle: Text(
                  facility.location,
                  style: GoogleFonts.poppins(fontSize: 12),
                ),
                selected: isSelected,
                selectedTileColor: Colors.blueGrey[50],
                onTap: () {
                  setState(() {
                    _selectedFacility = facility;
                  });
                },
              );
            },
          ),
        ),
        
        // Selected facility details
        if (_selectedFacility != null)
          Expanded(child: _buildFacilityDetails(_selectedFacility!)),
      ],
    );
  }

  Widget _buildFacilityDetails(Facility facility) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Facility header
          Row(
            children: [
              Icon(Icons.business, size: 32, color: Colors.blueGrey[700]),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      facility.name,
                      style: GoogleFonts.poppins(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: Colors.blueGrey[800],
                      ),
                    ),
                    Text(
                      'Location: ${facility.location}',
                      style: GoogleFonts.poppins(
                        fontSize: 16,
                        color: Colors.blueGrey[600],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          
          const SizedBox(height: 24),
          
          // Address section
          Card(
            elevation: 2,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.location_on, color: Colors.blueGrey[700]),
                      const SizedBox(width: 8),
                      Text(
                        'Address',
                        style: GoogleFonts.poppins(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.blueGrey[800],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    facility.address ?? 'No address provided',
                    style: GoogleFonts.poppins(
                      fontSize: 16,
                      color: Colors.blueGrey[700],
                    ),
                  ),
                ],
              ),
            ),
          ),
          
          const SizedBox(height: 24),
          
          // Map placeholder
          Card(
            elevation: 2,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: Column(
              children: [
                Container(
                  height: 300,
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: Colors.grey[200],
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
                  ),
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.map, size: 64, color: Colors.grey[400]),
                        const SizedBox(height: 16),
                        Text(
                          'Map View Coming Soon',
                          style: GoogleFonts.poppins(
                            fontSize: 18,
                            color: Colors.grey[600],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      ElevatedButton.icon(
                        onPressed: () => _showMapView(facility),
                        icon: const Icon(Icons.map),
                        label: Text('View Map', style: GoogleFonts.poppins()),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blueGrey[700],
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          
          const SizedBox(height: 24),
          
          // Additional information
          Card(
            elevation: 2,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.info_outline, color: Colors.blueGrey[700]),
                      const SizedBox(width: 8),
                      Text(
                        'Additional Information',
                        style: GoogleFonts.poppins(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.blueGrey[800],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  _buildInfoRow('Created', facility.createdAt.toLocal().toString().split(' ')[0]),
                  _buildInfoRow('Facility ID', facility.id),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              '$label:',
              style: GoogleFonts.poppins(
                fontWeight: FontWeight.w500,
                color: Colors.blueGrey[700],
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: GoogleFonts.poppins(color: Colors.blueGrey[800]),
            ),
          ),
        ],
      ),
    );
  }
}