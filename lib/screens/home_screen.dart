import 'package:flutter/material.dart';
import 'package:responsive_builder/responsive_builder.dart';
import 'package:cmms/widgets/sidebar.dart';
import 'package:cmms/widgets/mobile_menu.dart';
import 'package:cmms/screens/work_order_screen.dart';
import 'package:cmms/screens/request_screen.dart';
import 'package:cmms/screens/documentations_screen.dart';
import 'package:cmms/screens/drawings_screen.dart';
import 'package:cmms/screens/equipment_supplied_screen.dart';
import 'package:cmms/screens/inventory_screen.dart';
import 'package:cmms/screens/preventive_maintenance_screen.dart';
import 'package:cmms/screens/location_screen.dart';
import 'package:cmms/screens/vendor_screen.dart';
import 'package:cmms/screens/user_screen.dart';
import 'package:cmms/screens/report_screen.dart';
import 'package:cmms/screens/kpi_screen.dart';
import 'package:cmms/screens/building_survey_screen.dart';
import 'package:cmms/screens/schedule_maintenance_screen.dart';
import 'package:cmms/screens/reports_screen.dart';
import 'package:cmms/screens/price_list_screen.dart';
import 'package:cmms/screens/inspections_screen.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_fonts/google_fonts.dart';

class HomeScreen extends StatefulWidget {
  final String facilityId;

  const HomeScreen({super.key, required this.facilityId});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  String _selectedSection = 'locations';
  String _selectedSubSection = 'locations';
  late String _currentFacilityId;

  @override
  void initState() {
    super.initState();
    _currentFacilityId = widget.facilityId;
  }

  void _onSectionSelected(String section, {String? subSection}) {
    if (!mounted) return;
    setState(() {
      _selectedSection = section;
      _selectedSubSection = subSection ?? section;
    });
  }

  void _onFacilityChanged(String newFacilityId) {
    if (!mounted) return;
    setState(() {
      _currentFacilityId = newFacilityId;
    });
  }

  void _showFacilityDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          'Select Facility',
          style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance.collection('facilities').snapshots(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snapshot.hasError) {
                return Text('Error: ${snapshot.error}');
              }
              if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                return const Text('No facilities available');
              }

              final facilities = snapshot.data!.docs;
              return ListView.builder(
                shrinkWrap: true,
                itemCount: facilities.length,
                itemBuilder: (context, index) {
                  final facility = facilities[index];
                  return ListTile(
                    title: Text(
                      facility['name'] ?? 'Unnamed Facility',
                      style: GoogleFonts.poppins(),
                    ),
                    subtitle: Text(facility['address'] ?? ''),
                    selected: facility.id == _currentFacilityId,
                    selectedTileColor: Colors.grey[200],
                    onTap: () {
                      _onFacilityChanged(facility.id);
                      Navigator.pop(context);
                    },
                  );
                },
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pushNamed(context, '/facilities'),
            child: const Text('Manage Facilities'),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionContent(String facilityId) {
    if (facilityId.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text('Please select a facility'),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _showFacilityDialog,
              child: const Text('Select Facility'),
            ),
          ],
        ),
      );
    }

    Widget content;
    switch (_selectedSection) {
      case 'locations':
        content = LocationScreen(facilityId: facilityId);
        break;
      case 'building_survey':
        switch (_selectedSubSection) {
          case 'building_survey':
            content = BuildingSurveyScreen(
              facilityId: facilityId,
              selectedSubSection: _selectedSubSection,
            );
            break;
          case 'drawings':
            content = DrawingsScreen(facilityId: facilityId);
            break;
          case 'documentations':
            content = DocumentationsScreen(facilityId: facilityId);
            break;
          default:
            content = BuildingSurveyScreen(
              facilityId: facilityId,
              selectedSubSection: _selectedSubSection,
            );
        }
        break;
      case 'schedule_maintenance':
        switch (_selectedSubSection) {
          case 'schedule_maintenance':
            content = ScheduleMaintenanceScreen(
              facilityId: facilityId,
              selectedSubSection: _selectedSubSection,
            );
            break;
          case 'preventive_maintenance':
            content = PreventiveMaintenanceScreen(facilityId: facilityId);
            break;
          case 'reports':
            content = ReportsScreen(facilityId: facilityId);
            break;
          default:
            content = ScheduleMaintenanceScreen(
              facilityId: facilityId,
              selectedSubSection: _selectedSubSection,
            );
        }
        break;
      case 'work_orders':
        content = WorkOrderScreen(facilityId: facilityId);
        break;
      case 'price_list':
        content = PriceListScreen(facilityId: facilityId);
        break;
      case 'requests':
        content = RequestScreen(facilityId: facilityId);
        break;
      case 'equipment_supplied':
        content = EquipmentSuppliedScreen(facilityId: facilityId);
        break;
      case 'inventory':
        content = InventoryScreen(facilityId: facilityId);
        break;
      case 'vendors':
        content = VendorScreen(facilityId: facilityId);
        break;
      case 'users':
        content = UserScreen(facilityId: facilityId);
        break;
      case 'reports':
        content = ReportScreen(facilityId: facilityId);
        break;
      case 'kpis':
        content = KpiScreen(facilityId: facilityId);
        break;
      case 'inspections':
        content = InspectionsScreen(facilityId: facilityId);
        break;
      default:
        content = LocationScreen(facilityId: facilityId);
    }
    return Card(
      elevation: 2,
      margin: const EdgeInsets.all(16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: content,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ScreenTypeLayout.builder(
      mobile: (_) => _buildMobileLayout(context),
      tablet: (_) => _buildTabletLayout(context),
      desktop: (_) => _buildDesktopLayout(context),
    );
  }

  Widget _buildMobileLayout(BuildContext context) {
    return Scaffold(
      key: const ValueKey('home_scaffold_mobile'),
      appBar: AppBar(
        backgroundColor: Colors.grey[900],
        centerTitle: true,
        title: Text(
          'Swedish Facility Management',
          style: GoogleFonts.poppins(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.w700,
          ),
        ),
        leading: Builder(
          builder: (context) => IconButton(
            icon: const Icon(Icons.menu, color: Colors.white, size: 28),
            onPressed: () => Scaffold.of(context).openDrawer(),
          ),
        ),
      ),
      drawer: MobileMenu(
        onSectionSelected: _onSectionSelected,
        selectedSection: _selectedSection,
        selectedSubSection: _selectedSubSection,
        onChangeFacility: _showFacilityDialog,
      ),
      body: _buildSectionContent(_currentFacilityId),
      backgroundColor: Colors.grey[100],
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _getBottomNavIndex(),
        onTap: (index) {
          switch (index) {
            case 0:
              _onSectionSelected('work_orders');
              break;
            case 1:
              _onSectionSelected('requests');
              break;
            case 2:
              _onSectionSelected('inspections');
              break;
            case 3:
              _onSectionSelected('schedule_maintenance', subSection: 'preventive_maintenance');
              break;
          }
        },
        backgroundColor: Colors.grey[900],
        selectedItemColor: Colors.white,
        unselectedItemColor: Colors.grey[400],
        selectedLabelStyle: GoogleFonts.poppins(fontSize: 12),
        unselectedLabelStyle: GoogleFonts.poppins(fontSize: 12),
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.work, size: 24),
            label: 'Work Orders',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.request_page, size: 24),
            label: 'Requests',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.checklist, size: 24),
            label: 'Inspections',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.build, size: 24),
            label: 'PM',
          ),
        ],
      ),
    );
  }

  int _getBottomNavIndex() {
    switch (_selectedSection) {
      case 'work_orders':
        return 0;
      case 'requests':
        return 1;
      case 'inspections':
        return 2;
      case 'schedule_maintenance':
        if (_selectedSubSection == 'preventive_maintenance') return 3;
        break;
    }
    return 0; // Default to Work Orders
  }

  Widget _buildTabletLayout(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    return Scaffold(
      key: const ValueKey('home_scaffold_tablet'),
      appBar: AppBar(
        backgroundColor: Colors.grey[900],
        centerTitle: true,
        title: Text(
          'Swedish Emb Facility Management',
          style: GoogleFonts.poppins(
            color: Colors.white,
            fontSize: 22,
            fontWeight: FontWeight.w700,
          ),
        ),
        leading: Padding(
          padding: const EdgeInsets.only(left: 16.0),
          child: Image.asset(
            'assets/icons/construction-site.png',
            width: 32,
            height: 32,
          ),
        ),
        leadingWidth: 56,
      ),
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Sidebar(
            onSectionSelected: _onSectionSelected,
            selectedSection: _selectedSection,
            selectedSubSection: _selectedSubSection,
            width: screenWidth * 0.25,
            onChangeFacility: _showFacilityDialog,
          ),
          Expanded(
            child: Container(
              color: Colors.grey[100],
              child: _buildSectionContent(_currentFacilityId),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDesktopLayout(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    return Scaffold(
      key: const ValueKey('home_scaffold_desktop'),
      appBar: AppBar(
        backgroundColor: Colors.grey[900],
        centerTitle: true,
        title: Text(
          'Swedish Emb Facility Management',
          style: GoogleFonts.poppins(
            color: Colors.white,
            fontSize: 24,
            fontWeight: FontWeight.w700,
          ),
        ),
        leading: Padding(
          padding: const EdgeInsets.only(left: 16.0),
          child: Image.asset(
            'assets/icons/construction-site.png',
            width: 32,
            height: 32,
          ),
        ),
        leadingWidth: 56,
      ),
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Sidebar(
            onSectionSelected: _onSectionSelected,
            selectedSection: _selectedSection,
            selectedSubSection: _selectedSubSection,
            width: screenWidth * 0.2,
            onChangeFacility: _showFacilityDialog,
          ),
          Expanded(
            child: Container(
              color: Colors.grey[100],
              child: _buildSectionContent(_currentFacilityId),
            ),
          ),
        ],
      ),
    );
  }
}