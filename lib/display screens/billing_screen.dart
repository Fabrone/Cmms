import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cmms/models/billing_data.dart';
import 'package:cmms/widgets/responsive_screen_wrapper.dart';
import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_pdfview/flutter_pdfview.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:logger/logger.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:url_launcher/url_launcher.dart';

class BillingScreen extends StatefulWidget {
  final String facilityId;
  final String userRole;

  const BillingScreen({super.key, required this.facilityId, required this.userRole});

  @override
  State<BillingScreen> createState() => _BillingScreenState();
}

class _BillingScreenState extends State<BillingScreen> {
  final logger = Logger(printer: PrettyPrinter());
  final TextEditingController _titleController = TextEditingController();
  double? _uploadProgress;
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  bool _showForm = false;
  bool _hasViewedDocument = false;
  String? _currentViewingDocId;

  @override
  void initState() {
    super.initState();
    logger.i('BillingScreen initialized with facilityId: ${widget.facilityId}, role: ${widget.userRole}');
  }

  @override
  void dispose() {
    _titleController.dispose();
    super.dispose();
  }

  bool get _isAdmin => widget.userRole == 'Admin';

  Future<void> _uploadDocument() async {
    if (!_isAdmin) {
      if (mounted) _showSnackBar('Only admins can upload billing documents');
      return;
    }

    try {
      logger.i('Starting document upload for facilityId: ${widget.facilityId}');
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf'],
        withData: kIsWeb,
      );
      if (result == null || result.files.isEmpty) {
        logger.w('No file selected');
        if (mounted) _showSnackBar('No file selected');
        return;
      }

      final platformFile = result.files.single;
      final fileName = platformFile.name;
      final user = FirebaseAuth.instance.currentUser;
      
      if (user == null) {
        logger.w('No authenticated user for upload');
        if (mounted) _showSnackBar('Please sign in to upload billing documents');
        return;
      }

      final title = _titleController.text.trim().isEmpty ? fileName : _titleController.text.trim();
      if (!mounted) return;

      final bool? confirmUpload = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('Confirm Upload', style: GoogleFonts.poppins(fontWeight: FontWeight.bold)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (kIsWeb) 
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.blue[100],
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    'WEB',
                    style: GoogleFonts.poppins(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: Colors.blue[800],
                    ),
                  ),
                ),
              const SizedBox(height: 8),
              Text('Do you want to upload the billing document: $fileName?', style: GoogleFonts.poppins()),
            ],
          ),
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
        logger.i('User cancelled billing document upload: $fileName');
        return;
      }

      if (!mounted) return;

      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => PopScope(
          canPop: false,
          child: AlertDialog(
            title: Text('Uploading: $fileName', style: GoogleFonts.poppins(fontWeight: FontWeight.bold)),
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
                if (kIsWeb) ...[
                  const SizedBox(height: 8),
                  Text(
                    'Web Upload',
                    style: GoogleFonts.poppins(
                      fontSize: 12,
                      color: Colors.blue[600],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      );

      final storageRef = FirebaseStorage.instance
          .ref()
          .child('facilities/${widget.facilityId}/billing_data/${DateTime.now().millisecondsSinceEpoch}_$fileName');

      late UploadTask uploadTask;
      
      if (kIsWeb || Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
        if (platformFile.bytes == null) {
          throw 'File bytes not available for web/desktop upload';
        }
        
        final metadata = SettableMetadata(
          contentType: 'application/pdf',
          customMetadata: {
            'uploadedBy': user.uid,
            'originalName': fileName,
            'platform': kIsWeb ? 'web' : Platform.operatingSystem,
          },
        );
        
        uploadTask = storageRef.putData(platformFile.bytes!, metadata);
      } else {
        if (platformFile.path == null) {
          throw 'File path not available for mobile upload';
        }
        
        final file = File(platformFile.path!);
        final metadata = SettableMetadata(
          contentType: 'application/pdf',
          customMetadata: {
            'uploadedBy': user.uid,
            'originalName': fileName,
            'platform': Platform.operatingSystem,
          },
        );
        
        uploadTask = storageRef.putFile(file, metadata);
      }

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

      await FirebaseFirestore.instance.collection('BillingData').add({
        'userId': user.uid,
        'title': title,
        'fileName': fileName,
        'downloadUrl': downloadUrl,
        'uploadedAt': FieldValue.serverTimestamp(),
        'facilityId': widget.facilityId,
        'status': 'pending',
        'approvalStatus': 'pending',
        'platform': kIsWeb ? 'web' : Platform.operatingSystem,
      });

      if (mounted) {
        Navigator.pop(context);
        _showSnackBar('Billing document uploaded successfully');
        _titleController.clear();
        setState(() => _showForm = false);
      }
      logger.i('Uploaded billing document: $fileName, url: $downloadUrl');
    } catch (e, stackTrace) {
      logger.e('Error uploading billing document: $e', stackTrace: stackTrace);
      if (mounted) {
        Navigator.pop(context);
        _showSnackBar('Error uploading billing document: $e');
      }
    } finally {
      if (mounted) {
        setState(() {
          _uploadProgress = null;
        });
      }
    }
  }

  Future<void> _viewDocument(String url, String fileName, String docId) async {
    if (!mounted) return;
    
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text('Loading document...', style: GoogleFonts.poppins()),
          ],
        ),
      ),
    );

    try {
      if (mounted) {
        setState(() {
          _hasViewedDocument = true;
          _currentViewingDocId = docId;
        });
      }

      logger.i('Viewing document: $fileName, url: $url');
      if (kIsWeb || Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
        Navigator.pop(context);
        final uri = Uri.parse(url);
        if (await canLaunchUrl(uri)) {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
        } else {
          throw 'Could not open billing document in browser';
        }
      } else if (Platform.isAndroid || Platform.isIOS) {
        if (fileName.toLowerCase().endsWith('.pdf')) {
          final tempDir = await getTemporaryDirectory();
          final filePath = '${tempDir.path}/$fileName';
          await Dio().download(url, filePath);
          final file = File(filePath);
          if (await file.exists()) {
            if (mounted) {
              Navigator.pop(context);
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => PDFViewerScreen(
                    filePath: filePath,
                    name: fileName,
                    facilityId: widget.facilityId,
                  ),
                ),
              );
            }
          } else {
            throw 'Failed to download PDF';
          }
        } else {
          Navigator.pop(context);
          throw 'Only PDF viewing supported on mobile';
        }
      }
    } catch (e, stackTrace) {
      logger.e('Error viewing billing document: $e', stackTrace: stackTrace);
      if (mounted) {
        Navigator.pop(context);
        _showSnackBar('Error viewing billing document: $e');
      }
    }
  }

  Future<void> _downloadDocument(String url, String fileName) async {
    if (!mounted) return;
    
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text('Downloading...', style: GoogleFonts.poppins()),
          ],
        ),
      ),
    );

    try {
      logger.i('Downloading document: $fileName, url: $url');
      if (kIsWeb || Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
        Navigator.pop(context);
        final uri = Uri.parse(url);
        if (await canLaunchUrl(uri)) {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
        } else {
          throw 'Could not download billing document';
        }
      } else if (Platform.isAndroid || Platform.isIOS) {
        bool permissionGranted = await _requestStoragePermission();
        if (!permissionGranted) {
          if (mounted) {
            Navigator.pop(context);
            _showSnackBar('Storage permission denied');
          }
          return;
        }

        final downloadsDir = await getExternalStorageDirectory();
        final filePath = '${downloadsDir!.path}/$fileName';
        await Dio().download(url, filePath);

        final file = File(filePath);
        if (await file.exists()) {
          if (mounted) {
            Navigator.pop(context);
            _showSnackBar('Billing document downloaded to $filePath');
          }
          logger.i('Downloaded billing document: $fileName to $filePath');
        } else {
          throw 'Failed to download billing document';
        }
      }
    } catch (e, stackTrace) {
      logger.e('Error downloading billing document: $e', stackTrace: stackTrace);
      if (mounted) {
        Navigator.pop(context);
        _showSnackBar('Error downloading billing document: $e');
      }
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

  Future<void> _updateBillingStatus(String docId, String newStatus) async {
    if (!_isAdmin) {
      if (mounted) _showSnackBar('Only admins can update billing status');
      return;
    }

    try {
      await FirebaseFirestore.instance.collection('BillingData').doc(docId).update({
        'status': newStatus,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      if (mounted) _showSnackBar('Billing status updated to $newStatus');
      logger.i('Updated billing status: $docId to $newStatus');
    } catch (e, stackTrace) {
      logger.e('Error updating billing status: $e', stackTrace: stackTrace);
      if (mounted) _showSnackBar('Error updating billing status: $e');
    }
  }

  Future<void> _updateApprovalStatus(String docId, String approvalStatus, String? notes) async {
    if (_isAdmin) {
      if (mounted) _showSnackBar('Admins cannot approve/decline their own documents');
      return;
    }

    if (!_hasViewedDocument || _currentViewingDocId != docId) {
      if (mounted) _showSnackBar('Please view the document first before approving or declining');
      return;
    }

    try {
      final user = FirebaseAuth.instance.currentUser;
      await FirebaseFirestore.instance.collection('BillingData').doc(docId).update({
        'approvalStatus': approvalStatus,
        'approvalNotes': notes,
        'approvedBy': user?.email ?? user?.uid,
        'approvedAt': FieldValue.serverTimestamp(),
      });
      if (mounted) _showSnackBar('Document $approvalStatus successfully');
      logger.i('Updated approval status: $docId to $approvalStatus');
    } catch (e, stackTrace) {
      logger.e('Error updating approval status: $e', stackTrace: stackTrace);
      if (mounted) _showSnackBar('Error updating approval status: $e');
    }
  }

  void _showSnackBar(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message, style: GoogleFonts.poppins())),
      );
    }
  }

  Color _getStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'paid':
        return Colors.green.shade600;
      case 'pending':
        return Colors.orange.shade600;
      case 'approved':
        return Colors.blue.shade600;
      case 'declined':
        return Colors.red.shade600;
      default:
        return Colors.grey.shade600;
    }
  }

  @override
  Widget build(BuildContext context) {
    return ResponsiveScreenWrapper(
      title: 'Billing',
      facilityId: widget.facilityId,
      currentRole: widget.userRole,
      organization: '-',
      floatingActionButton: _isAdmin
          ? FloatingActionButton.extended(
              onPressed: () => setState(() => _showForm = !_showForm),
              backgroundColor: Colors.blueGrey[800],
              icon: Icon(_showForm ? Icons.close : Icons.upload_file, color: Colors.white),
              label: Text(
                _showForm ? 'Cancel' : 'Upload Billing Document',
                style: GoogleFonts.poppins(color: Colors.white),
              ),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            )
          : null,
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
          if (_isAdmin && _showForm) _buildUploadForm(padding, fontSizeTitle, fontSizeSubtitle),
          const SizedBox(height: 24),
          Row(
            children: [
              Text(
                'Billing Documents',
                style: GoogleFonts.poppins(
                  fontWeight: FontWeight.bold,
                  fontSize: fontSizeTitle,
                  color: Colors.blueGrey[900],
                ),
              ),
              if (kIsWeb) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.blue[100],
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    'WEB',
                    style: GoogleFonts.poppins(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: Colors.blue[800],
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 16),
          StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
                .collection('BillingData')
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
                logger.w('No billing documents found for facilityId: ${widget.facilityId}');
                return Card(
                  elevation: 2,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  child: Padding(
                    padding: const EdgeInsets.all(32.0),
                    child: Column(
                      children: [
                        Icon(
                          Icons.receipt,
                          size: 64,
                          color: Colors.grey[400],
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'No billing documents uploaded yet',
                          style: GoogleFonts.poppins(
                            fontSize: fontSizeSubtitle,
                            color: Colors.grey[600],
                          ),
                        ),
                        if (_isAdmin) ...[
                          const SizedBox(height: 8),
                          Text(
                            'Tap the upload button to add your first billing document',
                            style: GoogleFonts.poppins(
                              fontSize: fontSizeSubtitle - 2,
                              color: Colors.grey[500],
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                );
              }
              logger.i('Found ${docs.length} billing documents');
              return isMobile
                  ? _buildBillingTable(docs, fontSizeSubtitle)
                  : _buildBillingList(docs, isMobile, fontSizeSubtitle);
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
                  Row(
                    children: [
                      Text(
                        'Upload Billing Document',
                        style: GoogleFonts.poppins(
                          fontSize: fontSizeTitle,
                          fontWeight: FontWeight.bold,
                          color: Colors.blueGrey[900],
                        ),
                      ),
                      if (kIsWeb) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.blue[100],
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            'WEB',
                            style: GoogleFonts.poppins(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: Colors.blue[800],
                            ),
                          ),
                        ),
                      ],
                    ],
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

  Widget _buildBillingTable(List<QueryDocumentSnapshot> docs, double fontSize) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Card(
        elevation: 4,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: DataTable(
          columns: [
            DataColumn(
              label: Text('Document', style: GoogleFonts.poppins(fontWeight: FontWeight.bold, fontSize: fontSize)),
            ),
            DataColumn(
              label: Text('Status', style: GoogleFonts.poppins(fontWeight: FontWeight.bold, fontSize: fontSize)),
            ),
            DataColumn(
              label: Text('Approval', style: GoogleFonts.poppins(fontWeight: FontWeight.bold, fontSize: fontSize)),
            ),
            DataColumn(
              label: Text('Actions', style: GoogleFonts.poppins(fontWeight: FontWeight.bold, fontSize: fontSize)),
            ),
          ],
          rows: docs.map((doc) {
            final billing = BillingData.fromSnapshot(doc);
            return DataRow(cells: [
              DataCell(
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(billing.title, style: GoogleFonts.poppins(fontSize: fontSize)),
                    Text(
                      billing.uploadedAt != null
                          ? DateFormat('MMM dd, yyyy').format(billing.uploadedAt!)
                          : 'Unknown date',
                      style: GoogleFonts.poppins(fontSize: fontSize - 2, color: Colors.grey[600]),
                    ),
                  ],
                ),
              ),
              DataCell(_buildStatusChip(billing.status, fontSize)),
              DataCell(_buildStatusChip(billing.approvalStatus, fontSize)),
              DataCell(_buildActionButtons(billing, true)),
            ]);
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildBillingList(List<QueryDocumentSnapshot> docs, bool isMobile, double fontSize) {
    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: docs.length,
      itemBuilder: (context, index) {
        final billing = BillingData.fromSnapshot(docs[index]);
        return _buildBillingCard(billing, isMobile, fontSize);
      },
    );
  }

  Widget _buildBillingCard(BillingData billing, bool isMobile, double fontSize) {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Row(
          children: [
            Icon(
              Icons.receipt,
              color: Colors.blueGrey[700],
              size: isMobile ? 32 : 36,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    billing.title,
                    style: GoogleFonts.poppins(
                      color: Colors.blueGrey[900],
                      fontWeight: FontWeight.w600,
                      fontSize: fontSize,
                    ),
                  ),
                  Text(
                    'Uploaded: ${billing.uploadedAt != null ? DateFormat('MMM dd, yyyy').format(billing.uploadedAt!) : 'Unknown date'}',
                    style: GoogleFonts.poppins(
                      fontSize: isMobile ? 12 : 14,
                      color: Colors.grey[600],
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    children: [
                      _buildStatusChip(billing.status, fontSize),
                      _buildStatusChip(billing.approvalStatus, fontSize),
                    ],
                  ),
                ],
              ),
            ),
            _buildActionButtons(billing, false),
          ],
        ),
      ),
    );
  }

  Widget _buildTextField(double fontSize) {
    return TextFormField(
      controller: _titleController,
      decoration: InputDecoration(
        labelText: 'Document Title (Optional)',
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

  Widget _buildStatusChip(String status, double fontSize) {
    return Chip(
      label: Text(
        status.toUpperCase(),
        style: GoogleFonts.poppins(
          color: Colors.white,
          fontSize: fontSize - 4,
          fontWeight: FontWeight.bold,
        ),
      ),
      backgroundColor: _getStatusColor(status),
      padding: const EdgeInsets.symmetric(horizontal: 8),
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );
  }

  Widget _buildActionButtons(BillingData billing, bool isCompact) {
    if (_isAdmin) {
      return PopupMenuButton<String>(
        onSelected: (value) {
          if (value == 'view') {
            _viewDocument(billing.downloadUrl, billing.fileName, billing.id);
          } else if (value == 'download') {
            _downloadDocument(billing.downloadUrl, billing.fileName);
          } else if (value == 'mark_paid') {
            _updateBillingStatus(billing.id, 'paid');
          } else if (value == 'mark_pending') {
            _updateBillingStatus(billing.id, 'pending');
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
            value: 'mark_paid',
            child: Row(
              children: [
                Icon(Icons.check_circle, color: Colors.green[700], size: 20),
                const SizedBox(width: 8),
                Text('Mark as Paid', style: GoogleFonts.poppins()),
              ],
            ),
          ),
          PopupMenuItem(
            value: 'mark_pending',
            child: Row(
              children: [
                Icon(Icons.pending, color: Colors.orange[700], size: 20),
                const SizedBox(width: 8),
                Text('Mark as Pending', style: GoogleFonts.poppins()),
              ],
            ),
          ),
        ],
        icon: const Icon(Icons.more_vert, color: Colors.blueGrey),
      );
    } else {
      final canApprove = _hasViewedDocument && _currentViewingDocId == billing.id;
      return PopupMenuButton<String>(
        onSelected: (value) {
          if (value == 'view') {
            _viewDocument(billing.downloadUrl, billing.fileName, billing.id);
          } else if (value == 'download') {
            _downloadDocument(billing.downloadUrl, billing.fileName);
          } else if (value == 'approve') {
            _updateApprovalStatus(billing.id, 'approved', null);
          } else if (value == 'decline') {
            _showDeclineDialog(billing.id);
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
            value: 'approve',
            enabled: canApprove,
            child: Row(
              children: [
                Icon(
                  Icons.thumb_up,
                  color: canApprove ? Colors.green[700] : Colors.grey,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Text(
                  'Approve',
                  style: GoogleFonts.poppins(
                    color: canApprove ? Colors.black : Colors.grey,
                  ),
                ),
              ],
            ),
          ),
          PopupMenuItem(
            value: 'decline',
            enabled: canApprove,
            child: Row(
              children: [
                Icon(
                  Icons.thumb_down,
                  color: canApprove ? Colors.red[700] : Colors.grey,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Text(
                  'Decline',
                  style: GoogleFonts.poppins(
                    color: canApprove ? Colors.black : Colors.grey,
                  ),
                ),
              ],
            ),
          ),
        ],
        icon: const Icon(Icons.more_vert, color: Colors.blueGrey),
      );
    }
  }

  void _showDeclineDialog(String docId) {
    final notesController = TextEditingController();
    if (!mounted) return;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Decline Document', style: GoogleFonts.poppins(fontWeight: FontWeight.bold)),
        content: TextFormField(
          controller: notesController,
          decoration: InputDecoration(
            labelText: 'Reason for declining (optional)',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
            labelStyle: GoogleFonts.poppins(color: Colors.grey[600]),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: Colors.blueGrey, width: 2),
            ),
          ),
          style: GoogleFonts.poppins(),
          maxLines: 3,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel', style: GoogleFonts.poppins()),
          ),
          ElevatedButton(
            onPressed: () {
              _updateApprovalStatus(docId, 'declined', notesController.text.trim());
              Navigator.pop(context);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red[700],
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: Text('Decline', style: GoogleFonts.poppins(color: Colors.white)),
          ),
        ],
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