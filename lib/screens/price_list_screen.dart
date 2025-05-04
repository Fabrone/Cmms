import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:file_picker/file_picker.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:logger/logger.dart';
import 'package:url_launcher/url_launcher.dart';

class PriceListScreen extends StatefulWidget {
  final String facilityId;

  const PriceListScreen({super.key, required this.facilityId});

  @override
  State<PriceListScreen> createState() => _PriceListScreenState();
}

class _PriceListScreenState extends State<PriceListScreen> {
  final TextEditingController _titleController = TextEditingController();
  final Logger _logger = Logger();
  final GlobalKey<ScaffoldMessengerState> _messengerKey = GlobalKey<ScaffoldMessengerState>();

  Future<void> _uploadPdf() async {
    final title = _titleController.text.trim();
    try {
      _logger.i('Initiating PDF upload: title=$title, facilityId=${widget.facilityId}, collection=price_list');

      // Pick a PDF file
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf'],
        allowMultiple: false,
      );

      if (result == null || result.files.isEmpty) {
        _logger.w('No PDF selected');
        _messengerKey.currentState?.showSnackBar(
          const SnackBar(content: Text('No PDF selected')),
        );
        return;
      }

      final file = result.files.single;
      final fileName = file.name;
      final fileBytes = file.bytes;

      if (fileBytes == null) {
        _logger.w('No file bytes available for $fileName');
        _messengerKey.currentState?.showSnackBar(
          const SnackBar(content: Text('Error reading PDF file')),
        );
        return;
      }

      // Upload to Firebase Storage
      final storagePath = 'facilities/${widget.facilityId}/price_list/$fileName';
      final storageRef = FirebaseStorage.instance.ref(storagePath);
      final uploadTask = storageRef.putData(fileBytes, SettableMetadata(contentType: 'application/pdf'));
      final snapshot = await uploadTask;
      final fileUrl = await snapshot.ref.getDownloadURL();

      // Save metadata to Firestore
      final docTitle = title.isNotEmpty ? title : fileName;
      await FirebaseFirestore.instance
          .collection('facilities')
          .doc(widget.facilityId)
          .collection('price_list')
          .add({
        'title': docTitle,
        'fileUrl': fileUrl,
        'uploadedAt': FieldValue.serverTimestamp(),
      });

      _logger.i('PDF uploaded successfully: $fileName, url=$fileUrl');
      _messengerKey.currentState?.showSnackBar(
        const SnackBar(content: Text('PDF uploaded successfully')),
      );
      _titleController.clear();
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
      _logger.i('PDF deleted successfully: $title');
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
                  'Price Lists',
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
                              labelText: 'PDF Title (Optional)',
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
                                labelText: 'PDF Title (Optional)',
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
                        .collection('price_list')
                        .orderBy('uploadedAt', descending: true)
                        .snapshots(),
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return const Center(child: CircularProgressIndicator());
                      }
                      if (snapshot.hasError) {
                        _logger.e('Firestore error: ${snapshot.error}', stackTrace: StackTrace.current);
                        return Center(child: Text('Error: ${snapshot.error}'));
                      }
                      if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                        return Center(
                          child: Text(
                            'No price lists uploaded',
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
                              .collection('price_list')
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
                                      color: hasValidUrl ? Colors.red : Colors.grey,
                                      size: isMobile ? 20 : 24,
                                    ),
                                    onPressed: hasValidUrl
                                        ? () => _deletePdf(fileUrl, title, docRef)
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