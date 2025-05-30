import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cmms/models/drawings.dart';
import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter_pdfview/flutter_pdfview.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:logger/logger.dart';
import 'package:open_file/open_file.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:url_launcher/url_launcher.dart';

class DrawingsScreen extends StatefulWidget {
  final String facilityId;

  const DrawingsScreen({super.key, required this.facilityId});

  @override
  State<DrawingsScreen> createState() => _DrawingsScreenState();
}

class _DrawingsScreenState extends State<DrawingsScreen> {
  final logger = Logger(printer: PrettyPrinter());
  final TextEditingController _titleController = TextEditingController();
  double? _uploadProgress;
  final GlobalKey<ScaffoldMessengerState> _messengerKey = GlobalKey<ScaffoldMessengerState>();
  String _selectedCategory = 'Architectural';

  static const Map<String, String> drawingCategories = {
    'Architectural': 'Architectural Drawings',
    'Structural': 'Structural Drawings',
    'Electrical': 'Electrical Drawings',
    'Mechanical': 'Mechanical Drawings',
    'Plumbing': 'Plumbing Drawings',
    'HVAC': 'HVAC Drawings',
    'Fire Safety': 'Fire Safety Drawings',
    'Site Plan': 'Site Plan',
  };

  @override
  void initState() {
    super.initState();
    logger.i('DrawingsScreen initialized with facilityId: ${widget.facilityId}');
  }

  @override
  void dispose() {
    _titleController.dispose();
    super.dispose();
  }

  Future<void> _uploadDocument() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf', 'dwg', 'dxf'],
      );
      if (result == null || result.files.isEmpty) return;

      final file = File(result.files.single.path!);
      final fileName = result.files.single.name;
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Please log in to upload drawings', style: GoogleFonts.poppins())),
          );
        }
        return;
      }

      final title = _titleController.text.trim().isEmpty ? fileName : _titleController.text.trim();
      if (!mounted) {
        logger.w('Widget not mounted, skipping confirmation dialog for $fileName');
        return;
      }

      final bool? confirmUpload = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('Confirm Upload', style: GoogleFonts.poppins()),
          content: Text(
            'Do you want to upload the file: $fileName?',
            style: GoogleFonts.poppins(),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text('Cancel', style: GoogleFonts.poppins()),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text('Upload', style: GoogleFonts.poppins()),
            ),
          ],
        ),
      );

      if (confirmUpload != true) {
        logger.i('User cancelled drawing upload: $fileName');
        return;
      }

      if (!mounted) {
        logger.w('Widget not mounted, skipping progress dialog for $fileName');
        return;
      }

      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => PopScope(
          canPop: false,
          child: AlertDialog(
            title: Text('Uploading $fileName', style: GoogleFonts.poppins()),
            content: StatefulBuilder(
              builder: (context, setDialogState) {
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    LinearProgressIndicator(
                      value: _uploadProgress,
                      backgroundColor: Colors.grey[300],
                      valueColor: const AlwaysStoppedAnimation<Color>(Colors.blueGrey),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _uploadProgress != null
                          ? '${(_uploadProgress! * 100).toStringAsFixed(0)}%'
                          : 'Starting upload...',
                      style: GoogleFonts.poppins(),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      );

      final storageRef = FirebaseStorage.instance
          .ref()
          .child('facilities/${widget.facilityId}/drawings/${DateTime.now().millisecondsSinceEpoch}_$fileName');
      final uploadTask = storageRef.putFile(file);

      uploadTask.snapshotEvents.listen((TaskSnapshot snapshot) {
        setState(() {
          _uploadProgress = snapshot.bytesTransferred / snapshot.totalBytes;
        });
      }, onError: (e) {
        logger.e('Upload progress error: $e');
      });

      await uploadTask;
      final downloadUrl = await storageRef.getDownloadURL();

      await FirebaseFirestore.instance.collection('Drawings').add({
        'userId': user.uid,
        'title': title,
        'fileName': fileName,
        'downloadUrl': downloadUrl,
        'uploadedAt': FieldValue.serverTimestamp(),
        'facilityId': widget.facilityId,
        'category': _selectedCategory,
      });

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Drawing uploaded successfully', style: GoogleFonts.poppins())),
        );
        _titleController.clear();
      }
      logger.i('Uploaded drawing: $fileName, URL: $downloadUrl, facilityId: ${widget.facilityId}');
    } catch (e) {
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error uploading drawing: $e', style: GoogleFonts.poppins())),
        );
      }
      logger.e('Error uploading drawing: $e');
    } finally {
      setState(() {
        _uploadProgress = null;
      });
    }
  }

  Future<void> _viewDocument(String url, String fileName) async {
    try {
      if (Platform.isAndroid || Platform.isIOS) {
        if (fileName.toLowerCase().endsWith('.pdf')) {
          final tempDir = await getTemporaryDirectory();
          final filePath = '${tempDir.path}/$fileName';
          await Dio().download(url, filePath);
          final file = File(filePath);
          if (await file.exists()) {
            if (mounted) {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => PDFViewerScreen(filePath: filePath, fileName: fileName),
                ),
              );
            }
          } else {
            throw 'Failed to download PDF';
          }
        } else {
          throw 'Only PDF viewing is supported on mobile';
        }
      } else {
        final uri = Uri.parse(url);
        if (await canLaunchUrl(uri)) {
          await launchUrl(uri, mode: LaunchMode.inAppWebView);
        } else {
          throw 'Could not open drawing';
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error viewing drawing: $e', style: GoogleFonts.poppins())),
        );
      }
      logger.e('Error viewing drawing: $e');
    }
  }

  Future<void> _downloadDocument(String url, String fileName) async {
    try {
      if (Platform.isAndroid || Platform.isIOS) {
        bool permissionGranted = await _requestStoragePermission();
        if (!permissionGranted) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Storage permission denied', style: GoogleFonts.poppins())),
            );
          }
          return;
        }

        final downloadsDir = await getExternalStorageDirectory();
        final filePath = '${downloadsDir!.path}/$fileName';
        await Dio().download(url, filePath);

        final file = File(filePath);
        if (await file.exists()) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Drawing downloaded to $filePath', style: GoogleFonts.poppins()),
                action: SnackBarAction(
                  label: 'Open',
                  onPressed: () => OpenFile.open(filePath),
                ),
              ),
            );
          }
          logger.i('Downloaded drawing: $fileName to $filePath');
        } else {
          throw 'Failed to download drawing';
        }
      } else {
        final uri = Uri.parse(url);
        if (await canLaunchUrl(uri)) {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
        } else {
          throw 'Could not download drawing';
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error downloading drawing: $e', style: GoogleFonts.poppins())),
        );
      }
      logger.e('Error downloading drawing: $e');
    }
  }

  Future<bool> _requestStoragePermission() async {
    if (Platform.isAndroid) {
      var status = await Permission.storage.status;
      if (!status.isGranted) {
        status = await Permission.storage.request();
      }
      if (!status.isGranted) {
        status = await Permission.manageExternalStorage.status;
        if (!status.isGranted) {
          status = await Permission.manageExternalStorage.request();
        }
      }
      return status.isGranted;
    }
    return true;
  }

  Future<void> _deleteDocument(String downloadUrl, String fileName, String docId) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Confirm Deletion', style: GoogleFonts.poppins()),
        content: Text('Are you sure you want to delete "$fileName"?', style: GoogleFonts.poppins()),
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
      logger.i('Deletion cancelled for: $fileName');
      return;
    }

    try {
      await FirebaseStorage.instance.refFromURL(downloadUrl).delete();
      await FirebaseFirestore.instance.collection('Drawings').doc(docId).delete();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Drawing deleted successfully', style: GoogleFonts.poppins())),
        );
      }
      logger.i('Deleted drawing: $fileName, docId: $docId');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error deleting drawing: $e', style: GoogleFonts.poppins())),
        );
      }
      logger.e('Error deleting drawing: $e');
    }
  }

  IconData _getFileIcon(String fileName) {
    final extension = fileName.toLowerCase().split('.').last;
    switch (extension) {
      case 'pdf':
        return Icons.picture_as_pdf;
      case 'dwg':
      case 'dxf':
        return Icons.architecture;
      default:
        return Icons.insert_drive_file;
    }
  }

  Color _getFileIconColor(String fileName) {
    final extension = fileName.toLowerCase().split('.').last;
    switch (extension) {
      case 'pdf':
        return Colors.red[600]!;
      case 'dwg':
      case 'dxf':
        return Colors.blue[600]!;
      default:
        return Colors.grey[600]!;
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isMobile = screenWidth <= 600;
    final isTablet = screenWidth > 600 && screenWidth <= 900;
    final padding = isMobile ? 16.0 : isTablet ? 24.0 : 32.0;
    final fontSizeTitle = isMobile ? 20.0 : isTablet ? 24.0 : 28.0;
    final fontSizeSubtitle = isMobile ? 14.0 : isTablet ? 16.0 : 18.0;
    final inputFontSize = isMobile ? 14.0 : 16.0;

    return PopScope(
      canPop: true,
      child: ScaffoldMessenger(
        key: _messengerKey,
        child: Scaffold(
          appBar: AppBar(
            title: Text(
              'Drawings',
              style: GoogleFonts.poppins(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: fontSizeTitle,
              ),
            ),
            backgroundColor: Colors.blueGrey[800],
            leading: IconButton(
              icon: const Icon(Icons.arrow_back, color: Colors.white),
              onPressed: () => Navigator.pop(context),
            ),
            elevation: 0,
          ),
          body: SafeArea(
            child: SingleChildScrollView(
              padding: EdgeInsets.all(padding),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Upload Drawing',
                    style: GoogleFonts.poppins(
                      fontWeight: FontWeight.bold,
                      fontSize: fontSizeTitle,
                      color: Colors.blueGrey[900],
                    ),
                  ),
                  const SizedBox(height: 16),
                  isMobile
                      ? Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _buildTextField(inputFontSize),
                            const SizedBox(height: 12),
                            _buildCategoryDropdown(inputFontSize),
                            const SizedBox(height: 12),
                            _buildUploadButton(inputFontSize),
                          ],
                        )
                      : Row(
                          children: [
                            Expanded(
                              flex: 2,
                              child: _buildTextField(inputFontSize),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              flex: 2,
                              child: _buildCategoryDropdown(inputFontSize),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              flex: 1,
                              child: _buildUploadButton(inputFontSize),
                            ),
                          ],
                        ),
                  const SizedBox(height: 24),
                  Text(
                    'Uploaded Drawings',
                    style: GoogleFonts.poppins(
                      fontWeight: FontWeight.bold,
                      fontSize: fontSizeTitle,
                      color: Colors.blueGrey[900],
                    ),
                  ),
                  const SizedBox(height: 16),
                  StreamBuilder<QuerySnapshot>(
                    stream: FirebaseFirestore.instance
                        .collection('Drawings')
                        .where('facilityId', isEqualTo: widget.facilityId)
                        .orderBy('uploadedAt', descending: true)
                        .snapshots(),
                    builder: (context, snapshot) {
                      if (snapshot.hasError) {
                        logger.e('StreamBuilder error: ${snapshot.error}');
                        return Text('Error: ${snapshot.error}', style: GoogleFonts.poppins());
                      }
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return const Center(child: CircularProgressIndicator());
                      }
                      final docs = snapshot.data?.docs ?? [];
                      if (docs.isEmpty) {
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8.0),
                          child: Text('No drawings uploaded yet', style: GoogleFonts.poppins()),
                        );
                      }
                      return ListView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: docs.length,
                        itemBuilder: (context, index) {
                          final drawing = Drawing.fromSnapshot(docs[index]);
                          return Card(
                            elevation: 2,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            margin: const EdgeInsets.symmetric(vertical: 6),
                            child: ListTile(
                              leading: Icon(
                                _getFileIcon(drawing.fileName),
                                color: _getFileIconColor(drawing.fileName),
                                size: isMobile ? 32 : 36,
                              ),
                              title: Text(
                                drawing.title,
                                style: GoogleFonts.poppins(
                                  color: Colors.blueGrey[900],
                                  fontWeight: FontWeight.w500,
                                  fontSize: fontSizeSubtitle,
                                ),
                              ),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Category: ${drawing.category}',
                                    style: GoogleFonts.poppins(
                                      fontSize: isMobile ? 12 : 14,
                                      color: Colors.grey[600],
                                    ),
                                  ),
                                  Text(
                                    'Uploaded: ${drawing.uploadedAt != null ? DateFormat('MMM dd, yyyy').format(drawing.uploadedAt!) : 'Unknown date'}',
                                    style: GoogleFonts.poppins(
                                      fontSize: isMobile ? 12 : 14,
                                      color: Colors.grey[600],
                                    ),
                                  ),
                                ],
                              ),
                              trailing: PopupMenuButton<String>(
                                onSelected: (value) {
                                  if (value == 'view') {
                                    _viewDocument(drawing.downloadUrl, drawing.fileName);
                                  } else if (value == 'download') {
                                    _downloadDocument(drawing.downloadUrl, drawing.fileName);
                                  } else if (value == 'delete') {
                                    _deleteDocument(drawing.downloadUrl, drawing.fileName, drawing.id);
                                  }
                                },
                                itemBuilder: (context) => [
                                  PopupMenuItem(
                                    value: 'view',
                                    child: Row(
                                      children: [
                                        Icon(Icons.visibility, color: Colors.blue[700], size: 20),
                                        const SizedBox(width: 8),
                                        Text('View', style: GoogleFonts.poppins()),
                                      ],
                                    ),
                                  ),
                                  PopupMenuItem(
                                    value: 'download',
                                    child: Row(
                                      children: [
                                        Icon(Icons.download, color: Colors.green[700], size: 20),
                                        const SizedBox(width: 8),
                                        Text('Download', style: GoogleFonts.poppins()),
                                      ],
                                    ),
                                  ),
                                  PopupMenuItem(
                                    value: 'delete',
                                    child: Row(
                                      children: [
                                        Icon(Icons.delete, color: Colors.red[700], size: 20),
                                        const SizedBox(width: 8),
                                        Text('Delete', style: GoogleFonts.poppins()),
                                      ],
                                    ),
                                  ),
                                ],
                                icon: const Icon(Icons.more_vert, color: Colors.blueGrey),
                              ),
                            ),
                          );
                        },
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTextField(double fontSize) {
    return TextField(
      controller: _titleController,
      decoration: InputDecoration(
        labelText: 'Drawing Title (Optional)',
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: Colors.grey[400]!, width: 1),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: Colors.blueGrey[800]!, width: 2),
        ),
        filled: true,
        fillColor: Colors.grey[100],
        contentPadding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
        labelStyle: GoogleFonts.poppins(color: Colors.grey[600]),
        hintStyle: GoogleFonts.poppins(color: Colors.grey[400]),
      ),
      style: GoogleFonts.poppins(fontSize: fontSize),
    );
  }

  Widget _buildCategoryDropdown(double fontSize) {
    return DropdownButtonFormField<String>(
      value: _selectedCategory,
      decoration: InputDecoration(
        labelText: 'Drawing Category',
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: Colors.grey[400]!, width: 1),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: Colors.blueGrey[800]!, width: 2),
        ),
        filled: true,
        fillColor: Colors.grey[100],
        contentPadding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
        labelStyle: GoogleFonts.poppins(color: Colors.grey[600]),
      ),
      items: drawingCategories.entries.map((entry) {
        return DropdownMenuItem<String>(
          value: entry.key,
          child: Text(
            entry.value,
            style: GoogleFonts.poppins(fontSize: fontSize),
          ),
        );
      }).toList(),
      onChanged: (value) {
        setState(() {
          _selectedCategory = value!;
        });
      },
      style: GoogleFonts.poppins(fontSize: fontSize, color: Colors.black),
    );
  }

  Widget _buildUploadButton(double fontSize) {
    return ElevatedButton.icon(
      onPressed: _uploadDocument,
      icon: const Icon(Icons.upload_file, color: Colors.white),
      label: Text(
        'Upload File',
        style: GoogleFonts.poppins(color: Colors.white, fontSize: fontSize),
      ),
      style: ElevatedButton.styleFrom(
        backgroundColor: Colors.blueGrey[800],
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        elevation: 2,
      ),
    );
  }
}

class PDFViewerScreen extends StatelessWidget {
  final String filePath;
  final String fileName;

  const PDFViewerScreen({super.key, required this.filePath, required this.fileName});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(fileName, style: GoogleFonts.poppins(color: Colors.white)),
        backgroundColor: Colors.blueGrey[800],
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: SafeArea(
        child: PDFView(
          filePath: filePath,
          enableSwipe: true,
          swipeHorizontal: false,
          autoSpacing: true,
          pageFling: true,
          onError: (error) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Error loading PDF: $error', style: GoogleFonts.poppins())),
            );
          },
        ),
      ),
    );
  }
}
