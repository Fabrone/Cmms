import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cmms/services/pdf_service.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:logger/logger.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:firebase_storage/firebase_storage.dart';

class BuildingSurveyScreen extends StatefulWidget {
  final String facilityId;
  final String selectedSubSection;
  const BuildingSurveyScreen({
    super.key,
    required this.facilityId,
    required this.selectedSubSection,
  });

  @override
  State<BuildingSurveyScreen> createState() => _BuildingSurveyScreenState();
}

class _BuildingSurveyScreenState extends State<BuildingSurveyScreen> {
  final TextEditingController _titleController = TextEditingController();
  final Logger _logger = Logger();
  final GlobalKey<ScaffoldMessengerState> _messengerKey = GlobalKey<ScaffoldMessengerState>();
  final PdfService _pdfService = PdfService();
  bool _isUploading = false;

  Future<void> _uploadPdf() async {
    if (_isUploading) return;

    final title = _titleController.text.trim();
    try {
      setState(() => _isUploading = true);
      _logger.i('Uploading PDF with title: $title, facilityId: ${widget.facilityId}, subSection: ${widget.selectedSubSection}');
      final collection = widget.selectedSubSection == 'drawings' ? 'drawings' : 'survey_pdfs';
      final url = await _pdfService.uploadFile(
        facilityId: widget.facilityId,
        collection: collection,
        title: title.isEmpty ? 'OriginalFilename' : title,
        allowedExtensions: ['pdf'],
        category: collection,
      );
      if (url != null) {
        _messengerKey.currentState?.showSnackBar(
          SnackBar(content: Text('PDF uploaded successfully', style: GoogleFonts.poppins())),
        );
        _titleController.clear();
      } else {
        _messengerKey.currentState?.showSnackBar(
          SnackBar(content: Text('No PDF selected', style: GoogleFonts.poppins())),
        );
      }
    } catch (e, stackTrace) {
      _logger.e('Error uploading PDF: $e', stackTrace: stackTrace);
      _messengerKey.currentState?.showSnackBar(
        SnackBar(content: Text('Error uploading PDF: ${e.toString()}', style: GoogleFonts.poppins())),
      );
    } finally {
      if (mounted) setState(() => _isUploading = false);
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
          SnackBar(content: Text('Cannot open PDF', style: GoogleFonts.poppins())),
        );
      }
    } catch (e, stackTrace) {
      _logger.e('Error downloading PDF: $e', stackTrace: stackTrace);
      _messengerKey.currentState?.showSnackBar(
        SnackBar(content: Text('Error downloading PDF: $e', style: GoogleFonts.poppins())),
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
        SnackBar(content: Text('Error viewing PDF: $e', style: GoogleFonts.poppins())),
      );
    }
  }

  Future<void> _deletePdf(String? fileUrl, String title, DocumentReference docRef) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Confirm Deletion', style: GoogleFonts.poppins()),
        content: Text('Are you sure you want to delete "$title"?', style: GoogleFonts.poppins()),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Cancel', style: GoogleFonts.poppins()),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text('Delete', style: GoogleFonts.poppins(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirm != true) {
      _logger.i('Deletion cancelled for: $title');
      return;
    }

    try {
      _logger.i('Deleting PDF document: $title, url: $fileUrl');
      
      // Attempt to delete the file from Firebase Storage only if fileUrl is valid
      if (fileUrl != null && fileUrl.isNotEmpty) {
        try {
          await FirebaseStorage.instance.refFromURL(fileUrl).delete();
          _logger.i('Successfully deleted file from storage: $fileUrl');
        } catch (storageError, stackTrace) {
          _logger.w('Error deleting file from storage: $storageError', stackTrace: stackTrace);
          // Log the error but continue with document deletion
        }
      } else {
        _logger.w('No valid fileUrl for title: $title, skipping storage deletion');
      }

      // Delete the Firestore document
      await docRef.delete();
      _logger.i('Successfully deleted Firestore document for: $title');

      _messengerKey.currentState?.showSnackBar(
        SnackBar(content: Text('PDF deleted successfully', style: GoogleFonts.poppins())),
      );
    } catch (e, stackTrace) {
      _logger.e('Error deleting PDF document: $e', stackTrace: stackTrace);
      _messengerKey.currentState?.showSnackBar(
        SnackBar(content: Text('Error deleting PDF: ${e.toString()}', style: GoogleFonts.poppins())),
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
    _logger.i('Building BuildingSurveyScreen: facilityId=${widget.facilityId}, subSection=${widget.selectedSubSection}');
    final isMobile = MediaQuery.of(context).size.width <= 600;
    final collection = widget.selectedSubSection == 'drawings' ? 'drawings' : 'survey_pdfs';
    final sectionTitle = widget.selectedSubSection == 'drawings' ? 'Drawings' : 'Building Survey';

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
                  sectionTitle,
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
                            decoration: InputDecoration(
                              labelText: '$sectionTitle PDF Title (Optional)',
                              border: const OutlineInputBorder(),
                            ),
                            style: GoogleFonts.poppins(fontSize: 14),
                          ),
                          const SizedBox(height: 10),
                          ElevatedButton(
                            onPressed: _isUploading ? null : _uploadPdf,
                            child: _isUploading
                                ? const CircularProgressIndicator()
                                : Text(
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
                              decoration: InputDecoration(
                                labelText: '$sectionTitle PDF Title (Optional)',
                                border: const OutlineInputBorder(),
                              ),
                              style: GoogleFonts.poppins(fontSize: 16),
                            ),
                          ),
                          const SizedBox(width: 10),
                          ElevatedButton(
                            onPressed: _isUploading ? null : _uploadPdf,
                            child: _isUploading
                                ? const CircularProgressIndicator()
                                : Text(
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
                        .collection(collection)
                        .orderBy('uploadedAt', descending: true)
                        .snapshots(),
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return const Center(child: CircularProgressIndicator());
                      }
                      if (snapshot.hasError) {
                        _logger.e('Firestore error: ${snapshot.error}', stackTrace: StackTrace.current);
                        return Center(child: Text('Error: ${snapshot.error}', style: GoogleFonts.poppins()));
                      }
                      if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                        return Center(
                          child: Text(
                            'No $sectionTitle PDFs uploaded',
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
                              .collection(collection)
                              .doc(doc.id);
                          final data = doc.data() as Map<String, dynamic>;
                          final fileUrl = data['fileUrl'] as String?;
                          final title = data['title'] as String? ?? 'Untitled';
                          final uploadedAt = data['uploadedAt'] != null
                              ? (data['uploadedAt'] as Timestamp).toDate().toString()
                              : 'N/A';
                          final hasValidUrl = fileUrl != null && fileUrl.isNotEmpty;

                          return Card(
                            child: ListTile(
                              leading: const Icon(Icons.picture_as_pdf, color: Colors.red),
                              title: Text(
                                title,
                                style: GoogleFonts.poppins(
                                  fontSize: isMobile ? 14 : 16,
                                  color: Colors.black87,
                                ),
                                overflow: TextOverflow.ellipsis,
                                maxLines: 1,
                              ),
                              subtitle: Text(
                                'Uploaded: $uploadedAt',
                                style: GoogleFonts.poppins(
                                  fontSize: isMobile ? 12 : 14,
                                  color: Colors.black54,
                                ),
                              ),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  TextButton(
                                    onPressed: hasValidUrl
                                        ? () => _downloadPdf(fileUrl, title)
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
                                        ? () => _viewPdf(fileUrl, title)
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
                                      color: Colors.red,
                                      size: isMobile ? 20 : 24,
                                    ),
                                    onPressed: () => _deletePdf(fileUrl, title, docRef),
                                    tooltip: 'Delete PDF',
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