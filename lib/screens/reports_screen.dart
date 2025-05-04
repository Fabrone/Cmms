import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:logger/logger.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:cmms/services/pdf_service.dart';
import 'package:google_fonts/google_fonts.dart';

class ReportsScreen extends StatefulWidget {
  final String facilityId;

  const ReportsScreen({super.key, required this.facilityId});

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  final TextEditingController _titleController = TextEditingController();
  final Logger _logger = Logger();
  final GlobalKey<ScaffoldMessengerState> _messengerKey = GlobalKey<ScaffoldMessengerState>();
  final PdfService _pdfService = PdfService();

  Future<void> _uploadPdf() async {
    final title = _titleController.text.trim();
    try {
      _logger.i('Uploading PDF with title: $title');
      final url = await _pdfService.uploadFile(
        facilityId: widget.facilityId,
        collection: 'reports',
        title: title.isEmpty ? 'OriginalFilename' : title,
        allowedExtensions: ['pdf'],
        category: 'reports',
      );
      if (url != null) {
        _messengerKey.currentState?.showSnackBar(
          const SnackBar(content: Text('PDF uploaded successfully')),
        );
        _titleController.clear();
      } else {
        _messengerKey.currentState?.showSnackBar(
          const SnackBar(content: Text('No PDF selected')),
        );
      }
    } catch (e, stackTrace) {
      _logger.e('Error uploading PDF: $e', stackTrace: stackTrace);
      _messengerKey.currentState?.showSnackBar(
        SnackBar(content: Text('Error uploading PDF: $e')),
      );
    }
  }

  Future<void> _downloadPdf(String url, String title) async {
    try {
      _logger.i('Attempting to download PDF: $url');
      final uri = Uri.parse(url);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        _logger.w('Cannot launch URL: $url');
        _messengerKey.currentState?.showSnackBar(
          const SnackBar(content: Text('Cannot open PDF')),
        );
      }
    } catch (e, stackTrace) {
      _logger.e('Error downloading PDF: $e', stackTrace: stackTrace);
      _messengerKey.currentState?.showSnackBar(
        SnackBar(content: Text('Error downloading PDF: $e')),
      );
    }
  }

  Future<void> _viewPdf(String url, String title) async {
    try {
      _logger.i('Navigating to view PDF: $url');
      await Navigator.pushNamed(
        context,
        '/pdf_viewer',
        arguments: {'url': url, 'title': title},
      );
    } catch (e, stackTrace) {
      _logger.e('Error viewing PDF: $e', stackTrace: stackTrace);
      _messengerKey.currentState?.showSnackBar(
        SnackBar(content: Text('Error viewing PDF: $e')),
      );
    }
  }

  Future<void> _deletePdf(String? fileUrl, String title, DocumentReference docRef) async {
    if (fileUrl == null || fileUrl.isEmpty) {
      _logger.w('No valid fileUrl for title: $title');
      _messengerKey.currentState?.showSnackBar(
        const SnackBar(content: Text('Error: No valid PDF URL')),
      );
      return;
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirm Deletion'),
        content: Text('Are you sure you want to delete "$title"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirm != true) {
      _logger.i('Deletion cancelled for: $title');
      return;
    }

    try {
      _logger.i('Deleting PDF: $title, url: $fileUrl');
      await FirebaseStorage.instance.refFromURL(fileUrl).delete();
      await docRef.delete();
      _messengerKey.currentState?.showSnackBar(
        const SnackBar(content: Text('PDF deleted successfully')),
      );
    } on FirebaseException catch (e, stackTrace) {
      _logger.e('Firebase error deleting PDF: ${e.code} - ${e.message}', stackTrace: stackTrace);
      _messengerKey.currentState?.showSnackBar(
        SnackBar(content: Text('Error deleting PDF: ${e.message ?? e.code}')),
      );
    } catch (e, stackTrace) {
      _logger.e('Unexpected error deleting PDF: $e', stackTrace: stackTrace);
      _messengerKey.currentState?.showSnackBar(
        SnackBar(content: Text('Error deleting PDF: $e')),
      );
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _logger.i('Building ReportsScreen: facilityId=${widget.facilityId}');
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
                  'Reports',
                  style: GoogleFonts.poppins(
                    fontWeight: FontWeight.bold,
                    fontSize: isMobile ? 20 : 24,
                  ),
                ),
                const SizedBox(height: 16),
                isMobile
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          TextField(
                            controller: _titleController,
                            decoration: const InputDecoration(
                              labelText: 'Report PDF Title (Optional)',
                              border: OutlineInputBorder(),
                            ),
                            style: GoogleFonts.poppins(fontSize: 14),
                          ),
                          const SizedBox(height: 10),
                          ElevatedButton(
                            onPressed: _uploadPdf,
                            child: Text(
                              'Upload PDF',
                              style: GoogleFonts.poppins(fontSize: 14),
                            ),
                          ),
                        ],
                      )
                    : Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _titleController,
                              decoration: const InputDecoration(
                                labelText: 'Report PDF Title (Optional)',
                                border: OutlineInputBorder(),
                              ),
                              style: GoogleFonts.poppins(fontSize: 16),
                            ),
                          ),
                          const SizedBox(width: 10),
                          ElevatedButton(
                            onPressed: _uploadPdf,
                            child: Text(
                              'Upload PDF',
                              style: GoogleFonts.poppins(fontSize: 16),
                            ),
                          ),
                        ],
                      ),
                const SizedBox(height: 16),
                Expanded(
                  child: StreamBuilder<QuerySnapshot>(
                    stream: FirebaseFirestore.instance
                        .collection('facilities')
                        .doc(widget.facilityId)
                        .collection('reports')
                        .orderBy('uploadedAt', descending: true)
                        .snapshots(),
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return const Center(child: CircularProgressIndicator());
                      }
                      if (snapshot.hasError) {
                        _logger.e('Firestore error: ${snapshot.error}');
                        return Center(child: Text('Error: ${snapshot.error}'));
                      }
                      if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                        return Center(
                          child: Text(
                            'No reports uploaded',
                            style: GoogleFonts.poppins(fontSize: 14),
                          ),
                        );
                      }

                      final docs = snapshot.data!.docs;
                      return ListView.builder(
                        itemCount: docs.length,
                        itemBuilder: (context, index) {
                          final doc = docs[index];
                          final docRef = FirebaseFirestore.instance
                              .collection('facilities')
                              .doc(widget.facilityId)
                              .collection('reports')
                              .doc(doc.id);
                          final data = doc.data() as Map<String, dynamic>;
                          final fileUrl = data.containsKey('fileUrl')
                              ? data['fileUrl']
                              : data.containsKey('pdfUrl')
                                  ? data['pdfUrl']
                                  : null;
                          final hasValidUrl = fileUrl != null && fileUrl.isNotEmpty;

                          return Card(
                            child: ListTile(
                              leading: const Icon(Icons.picture_as_pdf, color: Colors.red),
                              title: Text(
                                doc['title'] ?? 'Untitled',
                                style: GoogleFonts.poppins(
                                  fontSize: isMobile ? 14 : 16,
                                ),
                                overflow: TextOverflow.ellipsis,
                                maxLines: 1,
                              ),
                              subtitle: Text(
                                'Uploaded: ${doc['uploadedAt']?.toDate().toString() ?? 'N/A'}',
                                style: GoogleFonts.poppins(
                                  fontSize: isMobile ? 12 : 14,
                                ),
                              ),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  TextButton(
                                    onPressed: hasValidUrl
                                        ? () => _downloadPdf(fileUrl, doc['title'] ?? 'Untitled')
                                        : null,
                                    child: Text(
                                      'Download',
                                      style: GoogleFonts.poppins(
                                        color: hasValidUrl ? Colors.blue : Colors.grey,
                                        fontSize: isMobile ? 12 : 14,
                                      ),
                                    ),
                                  ),
                                  TextButton(
                                    onPressed: hasValidUrl
                                        ? () => _viewPdf(fileUrl, doc['title'] ?? 'Untitled')
                                        : null,
                                    child: Text(
                                      'View',
                                      style: GoogleFonts.poppins(
                                        color: hasValidUrl ? Colors.green : Colors.grey,
                                        fontSize: isMobile ? 12 : 14,
                                      ),
                                    ),
                                  ),
                                  IconButton(
                                    icon: Icon(
                                      Icons.delete,
                                      color: hasValidUrl ? Colors.red : Colors.grey,
                                      size: isMobile ? 20 : 24,
                                    ),
                                    onPressed: hasValidUrl
                                        ? () => _deletePdf(fileUrl, doc['title'] ?? 'Untitled', docRef)
                                        : null,
                                    tooltip: hasValidUrl ? 'Delete PDF' : 'No valid PDF URL',
                                  ),
                                ],
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
      ),
    );
  }
}