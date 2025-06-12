import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cmms/models/price_list.dart';
import 'package:cmms/widgets/responsive_screen_wrapper.dart';
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

class PriceListScreen extends StatefulWidget {
  final String facilityId;

  const PriceListScreen({super.key, required this.facilityId});

  @override
  State<PriceListScreen> createState() => _PriceListScreenState();
}

class _PriceListScreenState extends State<PriceListScreen> {
  final logger = Logger(printer: PrettyPrinter());
  final TextEditingController _titleController = TextEditingController();
  double? _uploadProgress;
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  bool _showForm = false;
  String _currentRole = 'User';
  String _organization = '-';

  @override
  void initState() {
    super.initState();
    _getCurrentUserRole();
    logger.i('PriceListScreen initialized with facilityId: ${widget.facilityId}');
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      logger.w('No authenticated user found on init');
    } else {
      logger.i('Authenticated user: ${user.uid}');
    }
  }

  Future<void> _getCurrentUserRole() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      final adminDoc = await FirebaseFirestore.instance.collection('Admins').doc(user.uid).get();
      final developerDoc = await FirebaseFirestore.instance.collection('Developers').doc(user.uid).get();
      final technicianDoc = await FirebaseFirestore.instance.collection('Technicians').doc(user.uid).get();
      final userDoc = await FirebaseFirestore.instance.collection('Users').doc(user.uid).get();

      String newRole = 'User';
      String newOrg = '-';

      if (adminDoc.exists) {
        newRole = 'Admin';
        newOrg = adminDoc.data()?['organization'] ?? '-';
      } else if (developerDoc.exists) {
        newRole = 'Technician';
        newOrg = 'JV Almacis';
      } else if (technicianDoc.exists) {
        newRole = 'Technician';
        newOrg = technicianDoc.data()?['organization'] ?? '-';
      } else if (userDoc.exists) {
        final userData = userDoc.data();
        if (userData != null && userData['role'] == 'Technician') {
          newRole = 'Technician';
          newOrg = '-';
        } else {
          newRole = 'User';
          newOrg = '-';
        }
      }

      if (mounted) {
        setState(() {
          _currentRole = newRole;
          _organization = newOrg;
        });
      }
    } catch (e) {
      logger.e('Error getting user role: $e');
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    super.dispose();
  }

  Future<void> _uploadDocument() async {
    try {
      logger.i('Starting document upload for facilityId: ${widget.facilityId}');
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf'],
      );
      if (result == null || result.files.isEmpty) {
        logger.w('No file selected');
        if (mounted) _showSnackBar('No file selected');
        return;
      }

      final file = File(result.files.single.path!);
      final fileName = result.files.single.name;
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        logger.w('No authenticated user for upload');
        if (mounted) _showSnackBar('Please sign in to upload price lists');
        return;
      }

      final title = _titleController.text.trim().isEmpty ? fileName : _titleController.text.trim();
      if (!mounted) return;

      final bool? confirmUpload = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('Confirm Upload', style: GoogleFonts.poppins()),
          content: Text('Do you want to upload the file: $fileName?', style: GoogleFonts.poppins()),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text('Cancel', style: GoogleFonts.poppins()),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blueGrey[800],
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              child: Text('Upload', style: GoogleFonts.poppins(color: Colors.white)),
            ),
          ],
        ),
      );

      if (confirmUpload != true) {
        logger.i('User cancelled price list upload: $fileName');
        return;
      }

      if (!mounted) return;

      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => PopScope(
          canPop: false,
          child: AlertDialog(
            title: Text('Uploading: $fileName', style: GoogleFonts.poppins()),
            content: Column(
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
            ),
          ),
        ),
      );

      final storageRef = FirebaseStorage.instance
          .ref()
          .child('facilities/${widget.facilityId}/price_list/${DateTime.now().millisecondsSinceEpoch}_$fileName');
      final uploadTask = storageRef.putFile(file);

      uploadTask.snapshotEvents.listen((TaskSnapshot snapshot) {
        if (mounted) {
          setState(() {
            _uploadProgress = snapshot.bytesTransferred / snapshot.totalBytes;
          });
        }
      }, onError: (e) {
        logger.e('Upload progress error: $e');
      });

      await uploadTask;
      final downloadUrl = await storageRef.getDownloadURL();

      await FirebaseFirestore.instance.collection('price_list').add({
        'userId': user.uid,
        'title': title,
        'fileName': fileName,
        'downloadUrl': downloadUrl,
        'uploadedAt': FieldValue.serverTimestamp(),
        'facilityId': widget.facilityId,
      });

      if (mounted) {
        Navigator.pop(context);
        _showSnackBar('Price list uploaded successfully');
        _titleController.clear();
        setState(() => _showForm = false);
      }
      logger.i('Uploaded price list: $fileName, url: $downloadUrl');
    } catch (e, stackTrace) {
      logger.e('Error uploading price list: $e', stackTrace: stackTrace);
      if (mounted) {
        Navigator.pop(context);
        _showSnackBar('Error uploading price list: $e');
      }
    } finally {
      if (mounted) {
        setState(() {
          _uploadProgress = null;
        });
      }
    }
  }

  Future<void> _viewDocument(String url, String fileName) async {
    try {
      logger.i('Viewing document: $fileName, url: $url');
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
                  builder: (context) => PDFViewerScreen(filePath: filePath, name: fileName, facilityId: widget.facilityId),
                ),
              );
            }
          } else {
            throw 'Failed to download PDF';
          }
        } else {
          throw 'Only PDF viewing supported on mobile';
        }
      } else {
        final uri = Uri.parse(url);
        if (await canLaunchUrl(uri)) {
          await launchUrl(uri, mode: LaunchMode.inAppWebView);
        } else {
          throw 'Could not open price list';
        }
      }
    } catch (e, stackTrace) {
      logger.e('Error viewing price list: $e', stackTrace: stackTrace);
      if (mounted) _showSnackBar('Error viewing price list: $e');
    }
  }

  Future<void> _downloadDocument(String url, String fileName) async {
    try {
      logger.i('Downloading document: $fileName, url: $url');
      if (Platform.isAndroid || Platform.isIOS) {
        bool permissionGranted = await _requestStoragePermission();
        if (!permissionGranted) {
          if (mounted) _showSnackBar('Storage permission denied');
          return;
        }

        final downloadsDir = await getExternalStorageDirectory();
        final filePath = '${downloadsDir!.path}/$fileName';
        await Dio().download(url, filePath);

        final file = File(filePath);
        if (await file.exists()) {
          if (mounted) {
            _showSnackBar('Price list downloaded to $filePath', action: SnackBarAction(
              label: 'Open',
              onPressed: () => OpenFile.open(filePath),
            ));
          }
          logger.i('Downloaded price list: $fileName to $filePath');
        } else {
          throw 'Failed to download price list';
        }
      } else {
        final uri = Uri.parse(url);
        if (await canLaunchUrl(uri)) {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
        } else {
          throw 'Could not download price list';
        }
      }
    } catch (e, stackTrace) {
      logger.e('Error downloading price list: $e', stackTrace: stackTrace);
      if (mounted) _showSnackBar('Error downloading price list: $e');
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
      logger.i('Storage permission status: $status');
      return status.isGranted;
    }
    return true;
  }

  Future<void> _deleteDocument(String downloadUrl, String fileName, String docId) async {
    logger.i('Attempting to delete document: $fileName, docId: $docId');
    if (!mounted) return;

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
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red[700],
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: Text('Delete', style: GoogleFonts.poppins(color: Colors.white)),
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
      await FirebaseFirestore.instance.collection('price_list').doc(docId).delete();
      if (mounted) _showSnackBar('Price list deleted successfully');
      logger.i('Deleted price list: $fileName, docId: $docId');
    } catch (e, stackTrace) {
      logger.e('Error deleting price list: $e', stackTrace: stackTrace);
      if (mounted) _showSnackBar('Error deleting price list: $e');
    }
  }

  void _showSnackBar(String message, {SnackBarAction? action}) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message, style: GoogleFonts.poppins()),
          action: action,
        ),
      );
    }
  }

  IconData _getFileIcon(String fileName) {
    return Icons.picture_as_pdf;
  }

  Color _getFileIconColor(String fileName) {
    return Colors.red.shade600;
  }

  @override
  Widget build(BuildContext context) {
    return ResponsiveScreenWrapper(
      title: 'Price Lists',
      facilityId: widget.facilityId,
      currentRole: _currentRole,
      organization: _organization,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => setState(() => _showForm = !_showForm),
        backgroundColor: Colors.blueGrey[800],
        icon: Icon(_showForm ? Icons.close : Icons.upload_file, color: Colors.white),
        label: Text(
          _showForm ? 'Cancel' : 'Upload Price List',
          style: GoogleFonts.poppins(color: Colors.white),
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
      child: _buildBody(),
    );
  }

  Widget _buildBody() {
    final screenWidth = MediaQuery.of(context).size.width;
    final isMobile = screenWidth <= 600;
    final padding = isMobile ? 16.0 : screenWidth <= 900 ? 24.0 : 32.0;
    final fontSizeTitle = isMobile ? 20.0 : screenWidth <= 900 ? 24.0 : 28.0;
    final fontSizeSubtitle = isMobile ? 14.0 : screenWidth <= 900 ? 16.0 : 18.0;

    return SingleChildScrollView(
      padding: EdgeInsets.all(padding),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_showForm) _buildUploadForm(padding, fontSizeTitle, fontSizeSubtitle),
          const SizedBox(height: 24),
          Text(
            'Uploaded Price Lists',
            style: GoogleFonts.poppins(
              fontWeight: FontWeight.bold,
              fontSize: fontSizeTitle,
              color: Colors.blueGrey[900],
            ),
          ),
          const SizedBox(height: 16),
          StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
                .collection('price_list')
                .where('facilityId', isEqualTo: widget.facilityId)
                .orderBy('uploadedAt', descending: true)
                .snapshots(),
            builder: (context, snapshot) {
              logger.i('StreamBuilder snapshot: connectionState=${snapshot.connectionState}, hasError=${snapshot.hasError}, docCount=${snapshot.data?.docs.length ?? 0}');
              if (snapshot.hasError) {
                logger.e('StreamBuilder error: ${snapshot.error}');
                return Text('Error: ${snapshot.error}', style: GoogleFonts.poppins());
              }
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              final docs = snapshot.data?.docs ?? [];
              if (docs.isEmpty) {
                logger.w('No price lists found for facilityId: ${widget.facilityId}');
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8.0),
                  child: Text('No price lists uploaded yet', style: GoogleFonts.poppins(fontSize: fontSizeSubtitle)),
                );
              }
              logger.i('Found ${docs.length} price lists');
              return ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: docs.length,
                itemBuilder: (context, index) {
                  final priceList = PriceList.fromSnapshot(docs[index]);
                  return _buildPriceListCard(priceList, isMobile, fontSizeSubtitle);
                },
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildUploadForm(double padding, double fontSizeTitle, double fontSizeSubtitle) {
    final isMobile = MediaQuery.of(context).size.width <= 600;

    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      margin: EdgeInsets.all(padding),
      child: Padding(
        padding: EdgeInsets.all(padding),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Upload Price List',
                    style: GoogleFonts.poppins(
                      fontSize: fontSizeTitle,
                      fontWeight: FontWeight.bold,
                      color: Colors.blueGrey[900],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.blueGrey),
                    onPressed: () => setState(() => _showForm = false),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              isMobile
                  ? Column(
                      children: [
                        _buildTextField(fontSizeSubtitle),
                        const SizedBox(height: 16),
                        _buildUploadButton(fontSizeSubtitle),
                      ],
                    )
                  : Row(
                      children: [
                        Expanded(child: _buildTextField(fontSizeSubtitle)),
                        const SizedBox(width: 16),
                        _buildUploadButton(fontSizeSubtitle),
                      ],
                    ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPriceListCard(PriceList priceList, bool isMobile, double fontSize) {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Row(
          children: [
            Icon(
              _getFileIcon(priceList.fileName),
              color: _getFileIconColor(priceList.fileName),
              size: isMobile ? 32 : 36,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    priceList.title,
                    style: GoogleFonts.poppins(
                      color: Colors.blueGrey[900],
                      fontWeight: FontWeight.w600,
                      fontSize: fontSize,
                    ),
                  ),
                  Text(
                    'Uploaded: ${priceList.uploadedAt != null ? DateFormat('MMM dd, yyyy').format(priceList.uploadedAt!) : 'Unknown date'}',
                    style: GoogleFonts.poppins(
                      fontSize: isMobile ? 12 : 14,
                      color: Colors.grey[600],
                    ),
                  ),
                ],
              ),
            ),
            PopupMenuButton<String>(
              onSelected: (value) {
                if (value == 'view') {
                  _viewDocument(priceList.downloadUrl, priceList.fileName);
                } else if (value == 'download') {
                  _downloadDocument(priceList.downloadUrl, priceList.fileName);
                } else if (value == 'delete') {
                  _deleteDocument(priceList.downloadUrl, priceList.fileName, priceList.id);
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
          ],
        ),
      ),
    );
  }

  Widget _buildTextField(double fontSize) {
    return TextFormField(
      controller: _titleController,
      decoration: InputDecoration(
        labelText: 'Price List Title (Optional)',
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: Colors.grey[400] ?? Colors.grey),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Colors.blueGrey, width: 2),
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

  Widget _buildUploadButton(double fontSize) {
    return ElevatedButton.icon(
      onPressed: _uploadDocument,
      icon: const Icon(Icons.upload_file, color: Colors.white),
      label: Text(
        'Upload PDF',
        style: GoogleFonts.poppins(color: Colors.white, fontSize: fontSize),
      ),
      style: ElevatedButton.styleFrom(
        backgroundColor: Colors.blueGrey[800],
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        elevation: 4,
      ),
    );
  }
}

class PDFViewerScreen extends StatelessWidget {
  final String filePath;
  final String name;
  final String facilityId;

  const PDFViewerScreen({
    super.key,
    required this.filePath,
    required this.name,
    required this.facilityId,
  });

  @override
  Widget build(BuildContext context) {
    return ResponsiveScreenWrapper(
      title: name,
      facilityId: facilityId,
      currentRole: 'User',
      organization: '-',
      child: SafeArea(
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