import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:file_picker/file_picker.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:logger/logger.dart';
import 'package:url_launcher/url_launcher.dart';

class DocumentationsScreen extends StatefulWidget {
  final String facilityId;

  const DocumentationsScreen({super.key, required this.facilityId});

  @override
  State<DocumentationsScreen> createState() => _DocumentationsScreenState();
}

class _DocumentationsScreenState extends State<DocumentationsScreen> {
  final TextEditingController _titleController = TextEditingController();
  final Logger _logger = Logger();
  final GlobalKey<ScaffoldMessengerState> _messengerKey = GlobalKey<ScaffoldMessengerState>();
  String _selectedCategory = 'Building Information';
  bool _isUploading = false;
  bool _isInitializing = true;
  bool _useFallbackQuery = false;
  bool _hasIndexError = false;

  static const Map<String, String> documentCategories = {
    'Building Information': 'Building Info',
    'Floor Plans': 'Floor Plans',
    'MEP Layouts': 'MEP Layouts',
    'Fire Safety': 'Fire Safety',
    'Compliance': 'Compliance',
    'Maintenance': 'Maintenance',
    'Waste Management': 'Waste Management',
    'Contractors': 'Contractors',
    'Land Rates': 'Land Rates',
  };

  static const Map<String, String> categoryDescriptions = {
    'Building Information': 'Building Information',
    'Floor Plans': 'Latest Architectural Floor Plans (PDF or CAD)',
    'MEP Layouts': 'MEP (Mechanical, Electrical, Plumbing) Layout Drawings',
    'Fire Safety': 'Fire Safety System Design, Certifications and Test Reports',
    'Compliance': 'Compliance and Safety',
    'Maintenance': 'Past Maintenance Reports and Safety Audits',
    'Waste Management': 'Waste Management Plan and Disposal Licenses',
    'Contractors': 'List of Contractors Not Included in FM Agreement',
    'Land Rates': 'Land Rates',
  };

  Future<void> prepareFirestore() async {
    try {
      setState(() => _isInitializing = true);
      _logger.i('Preparing Firestore for facility: ${widget.facilityId}');

      // Ensure Firestore is active with a server query
      await FirebaseFirestore.instance
          .collection('facilities')
          .doc(widget.facilityId)
          .get(const GetOptions(source: Source.server));
      _logger.i('Firestore connection verified');

      // Fix documents
      final docs = await FirebaseFirestore.instance
          .collection('facilities')
          .doc(widget.facilityId)
          .collection('documentations')
          .get(const GetOptions(source: Source.server));
      int fixedCount = 0;
      for (var doc in docs.docs) {
        final data = doc.data();
        bool needsUpdate = false;
        final updates = <String, dynamic>{};

        if (data['category'] == null || !documentCategories.containsKey(data['category'])) {
          updates['category'] = 'Building Information';
          needsUpdate = true;
        }
        if (data['uploadedAt'] == null) {
          updates['uploadedAt'] = FieldValue.serverTimestamp();
          needsUpdate = true;
        }
        if (data['name'] == null) {
          updates['name'] = 'unknown.pdf';
          needsUpdate = true;
        }

        if (needsUpdate) {
          await doc.reference.update(updates);
          fixedCount++;
          _logger.i('Fixed document: ${doc.id} with updates: $updates');
        }
      }
      _logger.i('Document fix completed. Fixed $fixedCount documents.');
      if (fixedCount > 0) {
        _showSnackBar('Fixed $fixedCount documents');
      }
    } catch (e, stackTrace) {
      _logger.e('Error preparing Firestore: $e', stackTrace: stackTrace);
      _showSnackBar('Error preparing Firestore: $e');
    } finally {
      if (mounted) {
        setState(() => _isInitializing = false);
      }
    }
  }

  Future<void> _uploadPdf() async {
    if (_isUploading) return;

    final title = _titleController.text.trim();
    try {
      setState(() => _isUploading = true);
      _logger.i('Initiating PDF upload for facility: ${widget.facilityId}, category: $_selectedCategory');

      // Pick PDF file
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf'],
        allowMultiple: false,
      );

      if (result == null || result.files.isEmpty) {
        _logger.w('No PDF selected');
        _showSnackBar('No PDF selected');
        return;
      }

      final file = result.files.single;
      if (file.bytes == null || file.bytes!.isEmpty) {
        _logger.w('No file bytes available for ${file.name}');
        _showSnackBar('Error reading PDF file');
        return;
      }

      // Validate file size (e.g., max 10MB)
      const maxFileSize = 10 * 1024 * 1024; // 10MB in bytes
      if (file.bytes!.length > maxFileSize) {
        _logger.w('File size exceeds 10MB: ${file.name}');
        _showSnackBar('File size exceeds 10MB limit');
        return;
      }

      // Use a Firestore transaction for atomicity
      final storagePath = 'facilities/${widget.facilityId}/documentations/${DateTime.now().millisecondsSinceEpoch}_${file.name}';
      final storageRef = FirebaseStorage.instance.ref(storagePath);

      await FirebaseFirestore.instance.runTransaction((transaction) async {
        // Upload to Firebase Storage
        final uploadTask = storageRef.putData(file.bytes!, SettableMetadata(contentType: 'application/pdf'));
        final snapshot = await uploadTask;
        final fileUrl = await snapshot.ref.getDownloadURL();

        // Add document to Firestore
        final docRef = FirebaseFirestore.instance
            .collection('facilities')
            .doc(widget.facilityId)
            .collection('documentations')
            .doc();
        transaction.set(docRef, {
          'title': title.isNotEmpty ? title : file.name,
          'fileUrl': fileUrl,
          'category': _selectedCategory,
          'uploadedAt': FieldValue.serverTimestamp(),
          'name': file.name,
        });
      });

      _logger.i('PDF uploaded successfully: ${file.name}');
      _showSnackBar('PDF uploaded successfully');
      _titleController.clear();
    } catch (e, stackTrace) {
      _logger.e('Error uploading PDF: $e', stackTrace: stackTrace);
      String errorMessage = 'Error uploading PDF';
      if (e.toString().contains('storage/unauthorized')) {
        errorMessage = 'Permission denied. Check Firebase Storage rules.';
      } else if (e.toString().contains('storage/quota')) {
        errorMessage = 'Storage quota exceeded. Contact support.';
      }
      _showSnackBar(errorMessage);
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
        _showSnackBar('Cannot open PDF');
      }
    } catch (e, stackTrace) {
      _logger.e('Error downloading PDF: $e', stackTrace: stackTrace);
      _showSnackBar('Error downloading PDF: $e');
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
      _showSnackBar('Error viewing PDF: $e');
    }
  }

  Future<void> _deletePdf(String? fileUrl, String title, DocumentReference docRef) async {
    if (fileUrl == null || fileUrl.isEmpty) {
      _logger.w('No valid fileUrl for title: $title');
      _showSnackBar('Error: No valid PDF URL');
      return;
    }

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
      _logger.i('Deleting PDF: $title, url: $fileUrl');
      await FirebaseStorage.instance.refFromURL(fileUrl).delete();
      await docRef.delete();
      _logger.i('PDF deleted successfully: $title');
      _showSnackBar('PDF deleted successfully');
    } on FirebaseException catch (e, stackTrace) {
      _logger.e('Firebase error deleting PDF: ${e.code} - ${e.message}', stackTrace: stackTrace);
      _showSnackBar('Error deleting PDF: ${e.message ?? e.code}');
    } catch (e, stackTrace) {
      _logger.e('Unexpected error deleting PDF: $e', stackTrace: stackTrace);
      _showSnackBar('Error deleting PDF: $e');
    }
  }

  void _showSnackBar(String message) {
    _messengerKey.currentState?.showSnackBar(
      SnackBar(content: Text(message, style: GoogleFonts.poppins())),
    );
  }

  @override
  void initState() {
    super.initState();
    prepareFirestore();
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
        appBar: AppBar(
          title: Text('Documentation', style: GoogleFonts.poppins()),
        ),
        body: _isInitializing
            ? const Center(child: CircularProgressIndicator())
            : Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  children: [
                    _buildUploadSection(isMobile),
                    const SizedBox(height: 20),
                    Expanded(
                      child: _buildDocumentsList(),
                    ),
                  ],
                ),
              ),
      ),
    );
  }

  Widget _buildUploadSection(bool isMobile) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: isMobile
            ? Column(
                children: [
                  TextField(
                    controller: _titleController,
                    decoration: InputDecoration(
                      labelText: 'Document Title (Optional)',
                      border: const OutlineInputBorder(),
                      labelStyle: GoogleFonts.poppins(),
                    ),
                    style: GoogleFonts.poppins(),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    value: _selectedCategory,
                    items: documentCategories.entries.map((e) {
                      return DropdownMenuItem(
                        value: e.key,
                        child: Tooltip(
                          message: categoryDescriptions[e.key] ?? e.value,
                          child: Text(
                            e.value,
                            style: GoogleFonts.poppins(color: Colors.black),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      );
                    }).toList(),
                    onChanged: (value) => setState(() => _selectedCategory = value!),
                    decoration: InputDecoration(
                      labelText: 'Category',
                      border: const OutlineInputBorder(),
                      labelStyle: GoogleFonts.poppins(),
                    ),
                    style: GoogleFonts.poppins(color: Colors.black),
                    dropdownColor: Colors.white,
                    icon: const Icon(Icons.arrow_drop_down, color: Colors.black),
                    isExpanded: true,
                  ),
                  const SizedBox(height: 12),
                  ElevatedButton(
                    onPressed: _isUploading ? null : _uploadPdf,
                    child: _isUploading
                        ? const CircularProgressIndicator()
                        : Text('Upload PDF', style: GoogleFonts.poppins()),
                  ),
                ],
              )
            : Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _titleController,
                      decoration: InputDecoration(
                        labelText: 'Document Title (Optional)',
                        border: const OutlineInputBorder(),
                        labelStyle: GoogleFonts.poppins(),
                      ),
                      style: GoogleFonts.poppins(),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      value: _selectedCategory,
                      items: documentCategories.entries.map((e) {
                        return DropdownMenuItem(
                          value: e.key,
                          child: Tooltip(
                            message: categoryDescriptions[e.key] ?? e.value,
                            child: Text(
                              e.value,
                              style: GoogleFonts.poppins(color: Colors.black),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        );
                      }).toList(),
                      onChanged: (value) => setState(() => _selectedCategory = value!),
                      decoration: InputDecoration(
                        labelText: 'Category',
                        border: const OutlineInputBorder(),
                        labelStyle: GoogleFonts.poppins(),
                      ),
                      style: GoogleFonts.poppins(color: Colors.black),
                      dropdownColor: Colors.white,
                      icon: const Icon(Icons.arrow_drop_down, color: Colors.black),
                      isExpanded: true,
                    ),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton(
                    onPressed: _isUploading ? null : _uploadPdf,
                    child: _isUploading
                        ? const CircularProgressIndicator()
                        : Text('Upload PDF', style: GoogleFonts.poppins()),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _buildDocumentsList() {
    final isMobile = MediaQuery.of(context).size.width <= 600;

    return StreamBuilder<QuerySnapshot>(
      stream: _useFallbackQuery
          ? FirebaseFirestore.instance
              .collection('facilities')
              .doc(widget.facilityId)
              .collection('documentations')
              .where('category', isEqualTo: _selectedCategory)
              .snapshots()
          : FirebaseFirestore.instance
              .collection('facilities')
              .doc(widget.facilityId)
              .collection('documentations')
              .where('category', isEqualTo: _selectedCategory)
              .orderBy('uploadedAt', descending: true)
              .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (snapshot.hasError) {
          _logger.e('Error loading documents: ${snapshot.error}', stackTrace: snapshot.stackTrace);
          String errorMessage;
          if (snapshot.error.toString().contains('index')) {
            errorMessage = 'The query requires an index. Please create it in the Firebase Console: '
                'https://console.firebase.google.com/v1/r/project/cmms-e8a97/firestore/indexes?create_composite=ClFwcm9qZWN0cy9jbW1zLWU4YTk3L2RhdGFiYXNlcy8oZGVmYXVsdCkvY29sbGVjdGlvbkdyb3Vwcy9kb2N1bWVudGF0aW9ucy9pbmRleGVzL18QARoMCghjYXRlZ29yeRABGg4KCnVwbG9hZGVkQXQQAhoMCghfX25hbWVfXxAC';
            if (snapshot.error.toString().contains('index is being built')) {
              errorMessage = 'The required index is still building. Please try again later.';
            } else {
              // Schedule fallback query activation after build
              if (!_hasIndexError) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (mounted) {
                    setState(() {
                      _useFallbackQuery = true;
                      _hasIndexError = true;
                    });
                  }
                });
              }
              errorMessage += '\nUsing fallback query without sorting.';
            }
          } else {
            errorMessage = 'Error: ${snapshot.error}';
          }
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.error, color: Colors.red, size: 48),
                const SizedBox(height: 16),
                Text(
                  'Error loading documents',
                  style: GoogleFonts.poppins(fontSize: 16),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0),
                  child: Text(
                    errorMessage,
                    style: GoogleFonts.poppins(fontSize: 12),
                    textAlign: TextAlign.center,
                  ),
                ),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: () async {
                    if (mounted) {
                      setState(() {
                        _useFallbackQuery = false;
                        _hasIndexError = false;
                      });
                      await prepareFirestore();
                    }
                  },
                  child: Text('Retry', style: GoogleFonts.poppins()),
                ),
              ],
            ),
          );
        }

        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return Center(
            child: Text(
              'No documents found for this category',
              style: GoogleFonts.poppins(fontSize: 16),
            ),
          );
        }

        return ListView.builder(
          itemCount: snapshot.data!.docs.length,
          itemBuilder: (context, index) {
            final doc = snapshot.data!.docs[index];
            final data = doc.data() as Map<String, dynamic>;
            final docRef = doc.reference;
            final title = data['title'] ?? 'Untitled Document';
            final fileUrl = data['fileUrl'] as String?;
            final date = (data['uploadedAt'] as Timestamp?)?.toDate();
            final hasValidUrl = fileUrl != null && fileUrl.isNotEmpty;

            return Card(
              margin: const EdgeInsets.only(bottom: 12),
              child: ListTile(
                leading: const Icon(Icons.picture_as_pdf, color: Colors.red),
                title: Text(
                  title,
                  style: GoogleFonts.poppins(),
                ),
                subtitle: Text(
                  date != null ? 'Uploaded: ${date.toLocal().toString()}' : 'Upload date not available',
                  style: GoogleFonts.poppins(),
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextButton(
                      onPressed: hasValidUrl ? () => _downloadPdf(fileUrl, title) : null,
                      child: Text(
                        'Download',
                        style: GoogleFonts.poppins(
                          color: hasValidUrl ? Colors.blue : Colors.grey,
                          fontSize: isMobile ? 12 : 14,
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed: hasValidUrl ? () => _viewPdf(fileUrl, title) : null,
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
                      onPressed: hasValidUrl ? () => _deletePdf(fileUrl, title, docRef) : null,
                      tooltip: hasValidUrl ? 'Delete PDF' : 'No valid PDF URL',
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}