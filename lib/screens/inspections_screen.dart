import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:logger/logger.dart';
import 'package:rxdart/rxdart.dart' show CombineLatestStream;

class InspectionsScreen extends StatefulWidget {
  final String facilityId;

  const InspectionsScreen({super.key, required this.facilityId});

  @override
  State<InspectionsScreen> createState() => _InspectionsScreenState();
}

class _InspectionsScreenState extends State<InspectionsScreen> {
  final Logger _logger = Logger();
  final GlobalKey<ScaffoldMessengerState> _messengerKey = GlobalKey<ScaffoldMessengerState>();

  void _showSnackBar(String message) {
    _messengerKey.currentState?.showSnackBar(
      SnackBar(content: Text(message, style: GoogleFonts.poppins())),
    );
  }

  Future<void> _viewReport(String? reportId, String inspectionTitle) async {
    if (reportId == null || reportId.isEmpty) {
      _logger.w('No report ID for inspection: $inspectionTitle');
      _showSnackBar('No report available for this inspection');
      return;
    }
    try {
      _logger.i('Navigating to report: $reportId');
      await Navigator.pushNamed(
        context,
        '/reports',
        arguments: {'reportId': reportId, 'title': inspectionTitle},
      );
    } catch (e, stackTrace) {
      _logger.e('Error viewing report: $e', stackTrace: stackTrace);
      _showSnackBar('Error viewing report: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width <= 600;

    return ScaffoldMessenger(
      key: _messengerKey,
      child: Scaffold(
        appBar: AppBar(
          title: Text('Inspections', style: GoogleFonts.poppins()),
          backgroundColor: Colors.grey[900],
          foregroundColor: Colors.white,
        ),
        body: StreamBuilder<List<QuerySnapshot>>(
          stream: _combineInspectionStreams(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }

            if (snapshot.hasError) {
              _logger.e('Error loading inspections: ${snapshot.error}', stackTrace: snapshot.stackTrace);
              return Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.error, color: Colors.red, size: 48),
                    const SizedBox(height: 16),
                    Text(
                      'Error loading inspections',
                      style: GoogleFonts.poppins(fontSize: 16),
                    ),
                    Text(
                      'Error: ${snapshot.error}',
                      style: GoogleFonts.poppins(fontSize: 12),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: () => setState(() {}),
                      child: Text('Retry', style: GoogleFonts.poppins()),
                    ),
                  ],
                ),
              );
            }

            final docs = snapshot.data?.expand((query) => query.docs).toList() ?? [];
            if (docs.isEmpty) {
              return Center(
                child: Text(
                  'No upcoming inspections found',
                  style: GoogleFonts.poppins(fontSize: 16),
                ),
              );
            }

            return ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: docs.length,
              itemBuilder: (context, index) {
                final doc = docs[index];
                final data = doc.data() as Map<String, dynamic>;
                final title = data['title'] ?? 'Untitled Inspection';
                final dueDate = (data['dueDate'] as Timestamp?)?.toDate();
                final source = data['source'] ?? 'Unknown';
                final reportId = data['reportId'] as String?;
                final hasReport = reportId != null && reportId.isNotEmpty;

                return Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  child: ListTile(
                    leading: const Icon(Icons.checklist, color: Colors.blue),
                    title: Text(
                      title,
                      style: GoogleFonts.poppins(color: Colors.black87),
                    ),
                    subtitle: Text(
                      'Due: ${dueDate?.toLocal().toString().split('.')[0] ?? 'N/A'}\nSource: $source',
                      style: GoogleFonts.poppins(color: Colors.black54),
                    ),
                    trailing: TextButton(
                      onPressed: hasReport ? () => _viewReport(reportId, title) : null,
                      child: Text(
                        'View Report',
                        style: GoogleFonts.poppins(
                          color: hasReport ? Colors.green : Colors.grey,
                          fontSize: isMobile ? 12 : 14,
                        ),
                      ),
                    ),
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }

  Stream<List<QuerySnapshot>> _combineInspectionStreams() {
    final now = DateTime.now();
    final thirtyDaysFromNow = now.add(const Duration(days: 30));

    final requestsStream = FirebaseFirestore.instance
        .collection('facilities')
        .doc(widget.facilityId)
        .collection('requests')
        .where('type', isEqualTo: 'inspection')
        .where('dueDate', isGreaterThanOrEqualTo: Timestamp.fromDate(now))
        .where('dueDate', isLessThanOrEqualTo: Timestamp.fromDate(thirtyDaysFromNow))
        .where('status', whereIn: ['pending', 'due'])
        .snapshots()
        .map((snapshot) => snapshot..docs.forEach((doc) => doc.data()['source'] = 'Request'));

    final pmStream = FirebaseFirestore.instance
        .collection('facilities')
        .doc(widget.facilityId)
        .collection('preventive_maintenance')
        .where('taskType', isEqualTo: 'inspection')
        .where('dueDate', isGreaterThanOrEqualTo: Timestamp.fromDate(now))
        .where('dueDate', isLessThanOrEqualTo: Timestamp.fromDate(thirtyDaysFromNow))
        .where('status', whereIn: ['pending', 'due'])
        .snapshots()
        .map((snapshot) => snapshot..docs.forEach((doc) => doc.data()['source'] = 'Preventive Maintenance'));

    final woStream = FirebaseFirestore.instance
        .collection('facilities')
        .doc(widget.facilityId)
        .collection('work_orders')
        .where('isInspection', isEqualTo: true)
        .where('dueDate', isGreaterThanOrEqualTo: Timestamp.fromDate(now))
        .where('dueDate', isLessThanOrEqualTo: Timestamp.fromDate(thirtyDaysFromNow))
        .where('status', whereIn: ['pending', 'due'])
        .snapshots()
        .map((snapshot) => snapshot..docs.forEach((doc) => doc.data()['source'] = 'Work Order'));

    return CombineLatestStream.list([
      requestsStream,
      pmStream,
      woStream,
    ]);
  }
}