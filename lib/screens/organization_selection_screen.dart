import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:logger/logger.dart';
import 'package:cmms/models/organization.dart';

class OrganizationSelectionScreen extends StatefulWidget {
  final Function(String organizationId, String organizationName) onOrganizationSelected;

  const OrganizationSelectionScreen({
    super.key,
    required this.onOrganizationSelected,
  });

  @override
  OrganizationSelectionScreenState createState() => OrganizationSelectionScreenState();
}

class OrganizationSelectionScreenState extends State<OrganizationSelectionScreen> {
  final Logger logger = Logger(printer: PrettyPrinter());

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isMobile = screenWidth <= 600;
    final isDesktop = screenWidth > 1200;
    
    // Calculate content width - 60% for desktop, full width for mobile/tablet
    final contentWidth = isDesktop ? screenWidth * 0.6 : screenWidth;

    return SafeArea(
      child: Center(
        child: Container(
          width: contentWidth,
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header section
              Text(
                'Select Client Organization',
                style: GoogleFonts.poppins(
                  fontSize: isMobile ? 20 : 24,
                  fontWeight: FontWeight.bold,
                  color: Colors.blueGrey[800],
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Choose a client organization to manage its facilities',
                style: GoogleFonts.poppins(
                  fontSize: isMobile ? 14 : 16,
                  color: Colors.blueGrey[600],
                ),
              ),
              const SizedBox(height: 16),
              
              // Organizations list
              Expanded(
                child: StreamBuilder<QuerySnapshot>(
                  stream: FirebaseFirestore.instance
                      .collection('Organizations')
                      .where('isActive', isEqualTo: true)
                      .snapshots(),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(
                        child: CircularProgressIndicator(color: Colors.blueGrey),
                      );
                    }
                    
                    if (snapshot.hasError) {
                      logger.e('Firestore error: ${snapshot.error}');
                      return Center(
                        child: Text(
                          'Error: ${snapshot.error}',
                          style: GoogleFonts.poppins(color: Colors.red),
                        ),
                      );
                    }
                    
                    final docs = snapshot.data?.docs ?? [];
                    
                    // 🔧 UPDATED: Filter out JV Almacis ONLY from app launch selection
                    final clientOrganizations = docs
                        .map((doc) => Organization.fromFirestore(doc))
                        .where((org) => org.name != 'JV Almacis') // Exclude JV Almacis from app launch selection only
                        .toList();
                    
                    if (clientOrganizations.isEmpty) {
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
                              'No client organizations available',
                              style: GoogleFonts.poppins(
                                fontSize: isMobile ? 16 : 18,
                                color: Colors.blueGrey[600],
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Contact your administrator to add client organizations',
                              style: GoogleFonts.poppins(
                                fontSize: isMobile ? 14 : 16,
                                color: Colors.blueGrey[400],
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      );
                    }
                    
                    // Sort organizations alphabetically
                    clientOrganizations.sort((a, b) => a.name.compareTo(b.name));
                    
                    logger.i('Fetched ${clientOrganizations.length} client organizations for app launch selection (excluding JV Almacis)');

                    return ListView.builder(
                      itemCount: clientOrganizations.length,
                      itemBuilder: (context, index) {
                        final organization = clientOrganizations[index];

                        return GestureDetector(
                          onTap: () {
                            widget.onOrganizationSelected(organization.id, organization.name);
                            logger.i('Selected client organization: ${organization.name}, ID: ${organization.id}');
                          },
                          child: Card(
                            elevation: 2,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            color: Colors.white,
                            margin: const EdgeInsets.symmetric(vertical: 8),
                            child: Padding(
                              padding: const EdgeInsets.all(16.0),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Icon(
                                        Icons.business,
                                        color: Colors.blueGrey[600],
                                        size: isMobile ? 20 : 24,
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Text(
                                          organization.name,
                                          style: GoogleFonts.poppins(
                                            fontSize: isMobile ? 16 : 18,
                                            fontWeight: FontWeight.bold,
                                            color: Colors.blueGrey[800],
                                          ),
                                        ),
                                      ),
                                      // Client indicator for all organizations in this selection
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                        decoration: BoxDecoration(
                                          color: Colors.green[100],
                                          borderRadius: BorderRadius.circular(12),
                                        ),
                                        child: Text(
                                          'Client',
                                          style: GoogleFonts.poppins(
                                            fontSize: isMobile ? 10 : 12,
                                            fontWeight: FontWeight.w500,
                                            color: Colors.green[700],
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Icon(
                                        Icons.arrow_forward_ios,
                                        color: Colors.blueGrey[400],
                                        size: 16,
                                      ),
                                    ],
                                  ),
                                  if (organization.description != null && organization.description!.isNotEmpty) ...[
                                    const SizedBox(height: 8),
                                    Text(
                                      organization.description!,
                                      style: GoogleFonts.poppins(
                                        fontSize: isMobile ? 14 : 16,
                                        color: Colors.blueGrey[600],
                                      ),
                                    ),
                                  ],
                                  const SizedBox(height: 4),
                                  Text(
                                    'Added: ${organization.createdAt.toLocal().toString().split(' ')[0]}',
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
    );
  }
}