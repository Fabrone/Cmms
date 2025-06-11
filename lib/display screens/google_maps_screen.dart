import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:logger/logger.dart';

class GoogleMapsScreen extends StatefulWidget {
  final String facilityName;
  final String initialLocation;

  const GoogleMapsScreen({
    super.key,
    required this.facilityName,
    required this.initialLocation,
  });

  @override
  State<GoogleMapsScreen> createState() => _GoogleMapsScreenState();
}

class _GoogleMapsScreenState extends State<GoogleMapsScreen> {
  final Logger _logger = Logger(printer: PrettyPrinter());
  GoogleMapController? _mapController;
  Position? _currentPosition;
  LatLng? _facilityLocation;
  final Set<Marker> _markers = {};
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _initializeMap();
  }

  Future<void> _initializeMap() async {
    try {
      await _getCurrentLocation();
      await _geocodeLocation();
    } catch (e) {
      setState(() {
        _errorMessage = 'Error initializing map: $e';
        _isLoading = false;
      });
    }
  }

  Future<void> _getCurrentLocation() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        throw 'Location services are disabled.';
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          throw 'Location permissions are denied';
        }
      }

      if (permission == LocationPermission.deniedForever) {
        throw 'Location permissions are permanently denied.';
      }

      _currentPosition = await Geolocator.getCurrentPosition();
    } catch (e) {
      _logger.w('Could not get current location: $e');
    }
  }

  Future<void> _geocodeLocation() async {
    try {
      List<Location> locations = await locationFromAddress(
        '${widget.initialLocation}, Kenya'
      );
      
      if (locations.isNotEmpty) {
        _facilityLocation = LatLng(
          locations.first.latitude,
          locations.first.longitude,
        );
      }
    } catch (e) {
      _logger.w('Could not geocode location: $e');
      // Fallback to Nairobi coordinates
      _facilityLocation = const LatLng(-1.2921, 36.8219);
    }

    _updateMarkers();
    setState(() {
      _isLoading = false;
    });
  }

  void _updateMarkers() {
    _markers.clear();

    if (_currentPosition != null) {
      _markers.add(
        Marker(
          markerId: const MarkerId('current_location'),
          position: LatLng(_currentPosition!.latitude, _currentPosition!.longitude),
          infoWindow: const InfoWindow(
            title: 'Your Location',
            snippet: 'Current device location',
          ),
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueBlue),
        ),
      );
    }

    if (_facilityLocation != null) {
      _markers.add(
        Marker(
          markerId: const MarkerId('facility_location'),
          position: _facilityLocation!,
          infoWindow: InfoWindow(
            title: widget.facilityName,
            snippet: widget.initialLocation,
          ),
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
        ),
      );
    }
  }

  Future<void> _openInMapsApp() async {
    if (_facilityLocation != null) {
      final url = 'https://www.google.com/maps/search/?api=1&query=${_facilityLocation!.latitude},${_facilityLocation!.longitude}';
      if (await canLaunchUrl(Uri.parse(url))) {
        await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
      }
    }
  }

  Future<void> _getDirections() async {
    if (_currentPosition != null && _facilityLocation != null) {
      final url = 'https://www.google.com/maps/dir/${_currentPosition!.latitude},${_currentPosition!.longitude}/${_facilityLocation!.latitude},${_facilityLocation!.longitude}';
      if (await canLaunchUrl(Uri.parse(url))) {
        await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.facilityName,
          style: GoogleFonts.poppins(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
        backgroundColor: Colors.blueGrey,
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          IconButton(
            onPressed: _openInMapsApp,
            icon: const Icon(Icons.open_in_new),
            tooltip: 'Open in Maps App',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _errorMessage != null
              ? _buildErrorWidget()
              : _buildMapWidget(),
      floatingActionButton: _facilityLocation != null && _currentPosition != null
          ? FloatingActionButton.extended(
              onPressed: _getDirections,
              backgroundColor: Colors.blueGrey,
              icon: const Icon(Icons.directions, color: Colors.white),
              label: Text(
                'Directions',
                style: GoogleFonts.poppins(color: Colors.white),
              ),
            )
          : null,
    );
  }

  Widget _buildErrorWidget() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.error_outline,
              size: 64,
              color: Colors.red[400],
            ),
            const SizedBox(height: 16),
            Text(
              'Map Error',
              style: GoogleFonts.poppins(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Colors.red[700],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _errorMessage!,
              style: GoogleFonts.poppins(),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () => Navigator.pop(context),
              child: Text('Go Back', style: GoogleFonts.poppins()),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMapWidget() {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          color: Colors.blueGrey[50],
          child: Row(
            children: [
              Icon(Icons.info_outline, color: Colors.blueGrey[700]),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Blue marker: Your location • Red marker: ${widget.facilityName}',
                  style: GoogleFonts.poppins(
                    fontSize: 12,
                    color: Colors.blueGrey[700],
                  ),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: GoogleMap(
            onMapCreated: (GoogleMapController controller) {
              _mapController = controller;
            },
            initialCameraPosition: CameraPosition(
              target: _facilityLocation ?? const LatLng(-1.2921, 36.8219),
              zoom: 12,
            ),
            markers: _markers,
            myLocationEnabled: true,
            myLocationButtonEnabled: true,
            zoomControlsEnabled: true,
            mapToolbarEnabled: false,
          ),
        ),
        Container(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Location Details',
                style: GoogleFonts.poppins(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(Icons.location_city, color: Colors.blueGrey[700]),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      widget.facilityName,
                      style: GoogleFonts.poppins(),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  Icon(Icons.place, color: Colors.blueGrey[700]),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      widget.initialLocation,
                      style: GoogleFonts.poppins(),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  @override
  void dispose() {
    _mapController?.dispose();
    super.dispose();
  }
}