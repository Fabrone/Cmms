import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cmms/models/billing_data.dart';
import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
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
  final GlobalKey<ScaffoldMessengerState> _messengerKey = GlobalKey<ScaffoldMessengerState>();
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
      _showSnackBar('Only admins can upload billing documents');
      return;
    }

    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf'],
      );
      if (result == null || result.files.isEmpty) return;

      final file = File(result.files.single.path!);
      final fileName = result.files.single.name;
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        _showSnackBar('Please log in to upload billing documents');
        return;
      }

      final title = _titleController.text.trim().isEmpty ? fileName : _titleController.text.trim();
      
      // Check if widget is still mounted before using context
      if (!mounted) return;
      
      final bool? confirmUpload = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('Confirm Upload', style: GoogleFonts.poppins(fontWeight: FontWeight.bold)),
          content: Text(
            'Do you want to upload the billing document: $fileName?',
            style: GoogleFonts.poppins(),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text('Cancel', style: GoogleFonts.poppins()),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.blueGrey[800]),
              child: Text('Upload', style: GoogleFonts.poppins(color: Colors.white)),
            ),
          ],
        ),
      );

      if (confirmUpload != true) return;

      _showProgressDialog(fileName);

      final storageRef = FirebaseStorage.instance
          .ref()
          .child('facilities/${widget.facilityId}/billing_data/${DateTime.now().millisecondsSinceEpoch}_$fileName');
      final uploadTask = storageRef.putFile(file);

      uploadTask.snapshotEvents.listen((TaskSnapshot snapshot) {
        setState(() {
          _uploadProgress = snapshot.bytesTransferred / snapshot.totalBytes;
        });
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
      });

      if (mounted) {
        Navigator.of(context).pop(); // Close progress dialog
      }
      if (mounted) {
        _showSnackBar('Billing document uploaded successfully');
        _titleController.clear();
      }
      logger.i('Uploaded billing document: $fileName');
    } catch (e) {
      if (mounted) {
        Navigator.of(context).pop(); // Close progress dialog
        _showSnackBar('Error uploading billing document: $e');
      }
      logger.e('Error uploading billing document: $e');
    } finally {
      setState(() {
        _uploadProgress = null;
      });
    }
  }

  void _showProgressDialog(String fileName) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => PopScope(
        canPop: false,
        child: AlertDialog(
          title: Text('Uploading $fileName', style: GoogleFonts.poppins(fontWeight: FontWeight.bold)),
          content: StatefulBuilder(
            builder: (context, setDialogState) {
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  LinearProgressIndicator(
                    value: _uploadProgress,
                    backgroundColor: Colors.grey[300],
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.blueGrey[800]!),
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
  }

  Future<void> _viewDocument(String url, String fileName, String docId) async {
    try {
      setState(() {
        _hasViewedDocument = true;
        _currentViewingDocId = docId;
      });

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
          throw 'Could not open billing document';
        }
      }
    } catch (e) {
      _showSnackBar('Error viewing billing document: $e');
      logger.e('Error viewing billing document: $e');
    }
  }

  Future<void> _downloadDocument(String url, String fileName) async {
    try {
      if (Platform.isAndroid || Platform.isIOS) {
        bool permissionGranted = await _requestStoragePermission();
        if (!permissionGranted) {
          _showSnackBar('Storage permission denied');
          return;
        }

        final downloadsDir = await getExternalStorageDirectory();
        final filePath = '${downloadsDir!.path}/$fileName';
        await Dio().download(url, filePath);

        final file = File(filePath);
        if (await file.exists()) {
          _showSnackBar('Billing document downloaded to $filePath');
          logger.i('Downloaded billing document: $fileName to $filePath');
        } else {
          throw 'Failed to download billing document';
        }
      } else {
        final uri = Uri.parse(url);
        if (await canLaunchUrl(uri)) {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
        } else {
          throw 'Could not download billing document';
        }
      }
    } catch (e) {
      _showSnackBar('Error downloading billing document: $e');
      logger.e('Error downloading billing document: $e');
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

  Future<void> _updateBillingStatus(String docId, String newStatus) async {
    if (!_isAdmin) {
      _showSnackBar('Only admins can update billing status');
      return;
    }

    try {
      await FirebaseFirestore.instance.collection('BillingData').doc(docId).update({
        'status': newStatus,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      _showSnackBar('Billing status updated to $newStatus');
      logger.i('Updated billing status: $docId to $newStatus');
    } catch (e) {
      _showSnackBar('Error updating billing status: $e');
      logger.e('Error updating billing status: $e');
    }
  }

  Future<void> _updateApprovalStatus(String docId, String approvalStatus, String? notes) async {
    if (_isAdmin) {
      _showSnackBar('Admins cannot approve/decline their own documents');
      return;
    }

    if (!_hasViewedDocument || _currentViewingDocId != docId) {
      _showSnackBar('Please view the document first before approving or declining');
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
      _showSnackBar('Document $approvalStatus successfully');
      logger.i('Updated approval status: $docId to $approvalStatus');
    } catch (e) {
      _showSnackBar('Error updating approval status: $e');
      logger.e('Error updating approval status: $e');
    }
  }

  void _showSnackBar(String message) {
    _messengerKey.currentState?.showSnackBar(
      SnackBar(content: Text(message, style: GoogleFonts.poppins())),
    );
  }

  Color _getStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'paid':
        return Colors.green;
      case 'pending':
        return Colors.orange;
      case 'approved':
        return Colors.blue;
      case 'declined':
        return Colors.red;
      default:
        return Colors.grey;
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

    return PopScope(
      canPop: true,
      child: ScaffoldMessenger(
        key: _messengerKey,
        child: Scaffold(
          appBar: AppBar(
            title: Text(
              'Billing',
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
                  if (_isAdmin) ...[
                    Text(
                      'Upload Billing Document',
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
                              _buildTextField(fontSizeSubtitle),
                              const SizedBox(height: 12),
                              _buildUploadButton(fontSizeSubtitle),
                            ],
                          )
                        : Row(
                            children: [
                              Expanded(
                                flex: 3,
                                child: _buildTextField(fontSizeSubtitle),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                flex: 1,
                                child: _buildUploadButton(fontSizeSubtitle),
                              ),
                            ],
                          ),
                    const SizedBox(height: 24),
                  ],
                  Text(
                    'Billing Documents',
                    style: GoogleFonts.poppins(
                      fontWeight: FontWeight.bold,
                      fontSize: fontSizeTitle,
                      color: Colors.blueGrey[900],
                    ),
                  ),
                  const SizedBox(height: 16),
                  StreamBuilder<QuerySnapshot>(
                    stream: FirebaseFirestore.instance
                        .collection('BillingData')
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
                          child: Text('No billing documents uploaded yet', style: GoogleFonts.poppins()),
                        );
                      }

                      if (isMobile) {
                        return SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: DataTable(
                            columns: [
                              DataColumn(label: Text('Document', style: GoogleFonts.poppins(fontWeight: FontWeight.bold))),
                              DataColumn(label: Text('Status', style: GoogleFonts.poppins(fontWeight: FontWeight.bold))),
                              DataColumn(label: Text('Approval', style: GoogleFonts.poppins(fontWeight: FontWeight.bold))),
                              DataColumn(label: Text('Actions', style: GoogleFonts.poppins(fontWeight: FontWeight.bold))),
                            ],
                            rows: docs.map((doc) {
                              final billing = BillingData.fromSnapshot(doc);
                              return DataRow(cells: [
                                DataCell(
                                  Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(billing.title, style: GoogleFonts.poppins(fontSize: 12)),
                                      Text(
                                        billing.uploadedAt != null 
                                            ? DateFormat('MMM dd, yyyy').format(billing.uploadedAt!)
                                            : 'Unknown date',
                                        style: GoogleFonts.poppins(fontSize: 10, color: Colors.grey[600]),
                                      ),
                                    ],
                                  ),
                                ),
                                DataCell(_buildStatusChip(billing.status)),
                                DataCell(_buildStatusChip(billing.approvalStatus)),
                                DataCell(_buildActionButtons(billing, true)),
                              ]);
                            }).toList(),
                          ),
                        );
                      } else {
                        return ListView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: docs.length,
                          itemBuilder: (context, index) {
                            final billing = BillingData.fromSnapshot(docs[index]);
                            return Card(
                              elevation: 2,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              margin: const EdgeInsets.symmetric(vertical: 6),
                              child: ListTile(
                                leading: Icon(
                                  Icons.receipt,
                                  color: Colors.blueGrey[700],
                                  size: isMobile ? 32 : 36,
                                ),
                                title: Text(
                                  billing.title,
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
                                      'Uploaded: ${billing.uploadedAt != null ? DateFormat('MMM dd, yyyy').format(billing.uploadedAt!) : 'Unknown date'}',
                                      style: GoogleFonts.poppins(
                                        fontSize: isMobile ? 12 : 14,
                                        color: Colors.grey[600],
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Row(
                                      children: [
                                        _buildStatusChip(billing.status),
                                        const SizedBox(width: 8),
                                        _buildStatusChip(billing.approvalStatus),
                                      ],
                                    ),
                                  ],
                                ),
                                trailing: _buildActionButtons(billing, false),
                              ),
                            );
                          },
                        );
                      }
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
        labelText: 'Document Title (Optional)',
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
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        elevation: 2,
      ),
    );
  }

  Widget _buildStatusChip(String status) {
    return Chip(
      label: Text(
        status.toUpperCase(),
        style: GoogleFonts.poppins(
          color: Colors.white,
          fontSize: 10,
          fontWeight: FontWeight.bold,
        ),
      ),
      backgroundColor: _getStatusColor(status),
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
      // Technician view
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
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Decline Document', style: GoogleFonts.poppins(fontWeight: FontWeight.bold)),
        content: TextField(
          controller: notesController,
          decoration: InputDecoration(
            labelText: 'Reason for declining (optional)',
            border: const OutlineInputBorder(),
            labelStyle: GoogleFonts.poppins(),
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
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: Text('Decline', style: GoogleFonts.poppins(color: Colors.white)),
          ),
        ],
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
        title: Text(fileName, style: GoogleFonts.poppins(color: Colors.white, fontWeight: FontWeight.bold)),
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
