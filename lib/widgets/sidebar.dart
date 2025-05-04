import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class Sidebar extends StatelessWidget {
  final Function(String section, {String? subSection}) onSectionSelected;
  final String selectedSection;
  final String selectedSubSection;
  final double width;
  final VoidCallback onChangeFacility;

  const Sidebar({
    super.key,
    required this.onSectionSelected,
    required this.selectedSection,
    required this.selectedSubSection,
    required this.width,
    required this.onChangeFacility,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width.clamp(200, 300),
      color: Colors.grey[900],
      child: ListView(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 16.0, horizontal: 16.0),
            child: Image.asset(
              'assets/icons/construction-site.png',
              width: 48,
              height: 48,
            ),
          ),
          ListTile(
            leading: const Icon(Icons.business, color: Colors.white, size: 20),
            title: Text(
              'Facilities',
              style: GoogleFonts.poppins(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
            onTap: onChangeFacility,
          ),
          _buildSidebarItem(
            context,
            icon: Icons.location_on,
            title: 'Locations',
            section: 'locations',
            subSection: 'locations',
            isSelected: selectedSection == 'locations' && selectedSubSection == 'locations',
          ),
          _buildSidebarItem(
            context,
            icon: Icons.assessment,
            title: 'Building Survey',
            section: 'building_survey',
            subSection: 'building_survey',
            isSelected: selectedSection == 'building_survey' && selectedSubSection == 'building_survey',
          ),
          _buildSidebarItem(
            context,
            icon: Icons.map,
            title: 'Drawings',
            section: 'building_survey',
            subSection: 'drawings',
            isSelected: selectedSection == 'building_survey' && selectedSubSection == 'drawings',
            indent: true,
          ),
          _buildSidebarItem(
            context,
            icon: Icons.description,
            title: 'Documentations',
            section: 'building_survey',
            subSection: 'documentations',
            isSelected: selectedSection == 'building_survey' && selectedSubSection == 'documentations',
            indent: true,
          ),
          _buildSidebarItem(
            context,
            icon: Icons.schedule,
            title: 'Schedule Maintenance',
            section: 'schedule_maintenance',
            subSection: 'schedule_maintenance',
            isSelected: selectedSection == 'schedule_maintenance' && selectedSubSection == 'schedule_maintenance',
          ),
          _buildSidebarItem(
            context,
            icon: Icons.event_repeat,
            title: 'Preventive Maintenance',
            section: 'schedule_maintenance',
            subSection: 'preventive_maintenance',
            isSelected: selectedSection == 'schedule_maintenance' && selectedSubSection == 'preventive_maintenance',
            indent: true,
          ),
          _buildSidebarItem(
            context,
            icon: Icons.description,
            title: 'Reports',
            section: 'schedule_maintenance',
            subSection: 'reports',
            isSelected: selectedSection == 'schedule_maintenance' && selectedSubSection == 'reports',
            indent: true,
          ),
          _buildSidebarItem(
            context,
            icon: Icons.request_page,
            title: 'Price Lists',
            section: 'price_list',
            subSection: 'price_list',
            isSelected: selectedSection == 'price_list' && selectedSubSection == 'price_list',
          ),
          _buildSidebarItem(
            context,
            icon: Icons.request_page,
            title: 'Requests',
            section: 'requests',
            subSection: 'requests',
            isSelected: selectedSection == 'requests' && selectedSubSection == 'requests',
          ),
          _buildSidebarItem(
            context,
            icon: Icons.work,
            title: 'Work Orders',
            section: 'work_orders',
            subSection: 'work_orders',
            isSelected: selectedSection == 'work_orders' && selectedSubSection == 'work_orders',
          ),
          _buildSidebarItem(
            context,
            icon: Icons.build,
            title: 'Equipment Supplied',
            section: 'equipment_supplied',
            subSection: 'equipment_supplied',
            isSelected: selectedSection == 'equipment_supplied' && selectedSubSection == 'equipment_supplied',
          ),
          _buildSidebarItem(
            context,
            icon: Icons.inventory,
            title: 'Inventory',
            section: 'inventory',
            subSection: 'inventory',
            isSelected: selectedSection == 'inventory' && selectedSubSection == 'inventory',
          ),
          _buildSidebarItem(
            context,
            icon: Icons.store,
            title: 'Vendors',
            section: 'vendors',
            subSection: 'vendors',
            isSelected: selectedSection == 'vendors' && selectedSubSection == 'vendors',
          ),
          _buildSidebarItem(
            context,
            icon: Icons.person,
            title: 'Users',
            section: 'users',
            subSection: 'users',
            isSelected: selectedSection == 'users' && selectedSubSection == 'users',
          ),
          _buildSidebarItem(
            context,
            icon: Icons.bar_chart,
            title: 'Reports',
            section: 'reports',
            subSection: 'reports',
            isSelected: selectedSection == 'reports' && selectedSubSection == 'reports',
          ),
          _buildSidebarItem(
            context,
            icon: Icons.show_chart,
            title: 'KPIs',
            section: 'kpis',
            subSection: 'kpis',
            isSelected: selectedSection == 'kpis' && selectedSubSection == 'kpis',
          ),
        ],
      ),
    );
  }

  Widget _buildSidebarItem(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String section,
    required String subSection,
    required bool isSelected,
    bool indent = false,
  }) {
    return ListTile(
      leading: Icon(
        icon,
        color: Colors.white,
        size: isSelected ? 24 : 20,
      ),
      title: Text(
        title,
        style: GoogleFonts.poppins(
          color: Colors.white,
          fontSize: isSelected ? (indent ? 14 : 15) : (indent ? 13 : 14),
          fontWeight: indent ? FontWeight.normal : FontWeight.w600,
        ),
      ),
      tileColor: isSelected ? Colors.grey[800] : null,
      hoverColor: Colors.grey[700],
      contentPadding: EdgeInsets.only(
        left: indent ? 48.0 : 16.0,
        right: 16.0,
      ),
      onTap: () {
        onSectionSelected(section, subSection: subSection);
      },
    );
  }
}