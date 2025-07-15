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
import 'package:url_launcher/url_launcher.dart';

class BillingScreen extends StatefulWidget {
  final String facilityId;

  const BillingScreen({super.key, required this.facilityId, required String userRole});

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
  
  // User role information - using same pattern as work orders
  String _currentRole = 'User';
  String _organization = '-';
  bool _isJVAlmacisUser = false;
  bool _isAdminClient = false;

  @override
  void initState() {
    super.initState();
    _getCurrentUserInfo();
    logger.i('BillingScreen initialized with facilityId: ${widget.facilityId}');
  }

  @override
  void dispose() {
    _titleController.dispose();
    super.dispose();
  }

  Future<void> _getCurrentUserInfo() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      final adminDoc = await FirebaseFirestore.instance.collection('Admins').doc(user.uid).get();
      final developerDoc = await FirebaseFirestore.instance.collection('Developers').doc(user.uid).get();
      final technicianDoc = await FirebaseFirestore.instance.collection('Technicians').doc(user.uid).get();
      final userDoc = await FirebaseFirestore.instance.collection('Users').doc(user.uid).get();

      String newRole = 'User';
      String newOrg = '-';
      String? username;
      bool isClient = false;
      bool isJVAlmacisUser = false;
      bool isAdminClient = false;

      if (adminDoc.exists) {
        newRole = 'Admin';
        final data = adminDoc.data()!;
        newOrg = data['organization'] ?? '-';
        username = data['username'] ?? data['name'] ?? data['displayName'];
        isClient = newOrg != 'JV Almacis';
        isAdminClient = isClient;
        logger.i('User is Admin, org: $newOrg, isClient: $isClient, isAdminClient: $isAdminClient');
      } else if (developerDoc.exists) {
        newRole = 'Technician';
        newOrg = 'JV Almacis';
        final data = developerDoc.data()!;
        username = data['username'] ?? data['name'] ?? data['displayName'];
        isJVAlmacisUser = true;
        logger.i('User is Developer (JV Almacis), org: $newOrg');
      } else if (technicianDoc.exists) {
        newRole = 'Technician';
        final data = technicianDoc.data()!;
        newOrg = data['organization'] ?? '-';
        username = data['username'] ?? data['name'] ?? data['displayName'];
        isClient = newOrg != 'JV Almacis';
        isJVAlmacisUser = newOrg == 'JV Almacis';
        logger.i('User is Technician, org: $newOrg, isClient: $isClient, isJVAlmacis: $isJVAlmacisUser');
      } else if (userDoc.exists) {
        final userData = userDoc.data()!;
        if (userData['role'] == 'Technician') {
          newRole = 'Technician';
          newOrg = userData['organization'] ?? '-';
        } else {
          newRole = 'User';
          newOrg = userData['organization'] ?? '-';
        }
        username = userData['username'] ?? userData['name'] ?? userData['displayName'];
        isClient = newOrg != 'JV Almacis';
        isJVAlmacisUser = newOrg == 'JV Almacis';
        logger.i('User from Users collection, role: $newRole, org: $newOrg, isClient: $isClient');
      }

      if (mounted) {
        setState(() {
          _currentRole = newRole;
          _organization = newOrg;
          _isJVAlmacisUser = isJVAlmacisUser;
          _isAdminClient = isAdminClient;
        });
        logger.i('Updated user info for Billing: isJVAlmacis=$isJVAlmacisUser, isAdminClient=$isAdminClient, org=$newOrg, username=$username');
      }
    } catch (e) {
      logger.e('Error getting user info: $e');
    }
  }

  bool get _canUpload => _isJVAlmacisUser || _isAdmin;
  bool get _isAdmin => _currentRole == 'Admin';

  Future<void> _uploadAdminDocument() async {
    if (!_isAdmin) {
      _showSnackBar('Only admins can upload admin documents');
      return;
    }

    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf', 'doc', 'docx', 'xls', 'xlsx', 'pptx', 'txt'],
        withData: kIsWeb,
      );
      if (result == null || result.files.isEmpty) return;

      final platformFile = result.files.single;
      final fileName = platformFile.name;
      final user = FirebaseAuth.instance.currentUser;
      
      if (user == null) {
        _showSnackBar('Please sign in to upload documents');
        return;
      }

      if (!mounted) return;
      final bool? confirmUpload = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('Confirm Admin Document Upload', style: GoogleFonts.poppins(fontWeight: FontWeight.bold)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Upload admin document: $fileName?', style: GoogleFonts.poppins()),
              const SizedBox(height: 8),
              Text(
                'This will replace any existing admin document.',
                style: GoogleFonts.poppins(
                  fontSize: 12,
                  color: Colors.orange[700],
                  fontStyle: FontStyle.italic,
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text('Cancel', style: GoogleFonts.poppins()),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.green[800]),
              child: Text('Upload', style: GoogleFonts.poppins(color: Colors.white)),
            ),
          ],
        ),
      );

      if (confirmUpload != true) return;

      if (!mounted) return;
      _showUploadDialog(fileName);

      final storageRef = FirebaseStorage.instance
          .ref()
          .child('facilities/${widget.facilityId}/billing_data/${DateTime.now().millisecondsSinceEpoch}_$fileName');

      late UploadTask uploadTask;
      
      if (kIsWeb || Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
        uploadTask = storageRef.putData(platformFile.bytes!);
      } else {
        uploadTask = storageRef.putFile(File(platformFile.path!));
      }

      uploadTask.snapshotEvents.listen((snapshot) {
        if (mounted) {
          setState(() {
            _uploadProgress = snapshot.bytesTransferred / snapshot.totalBytes;
          });
        }
      });

      await uploadTask;
      final downloadUrl = await storageRef.getDownloadURL();

      final existingAdminDocs = await FirebaseFirestore.instance
          .collection('BillingData')
          .where('facilityId', isEqualTo: widget.facilityId)
          .where('isAdminDocument', isEqualTo: true)
          .get();
      
      for (var doc in existingAdminDocs.docs) {
        await doc.reference.delete();
      }

      await FirebaseFirestore.instance.collection('BillingData').add({
        'userId': user.uid,
        'title': fileName,
        'fileName': fileName,
        'downloadUrl': downloadUrl,
        'uploadedAt': FieldValue.serverTimestamp(),
        'facilityId': widget.facilityId,
        'status': 'pending',
        'approvalStatus': 'pending',
        'isAdminDocument': true,
        'platform': kIsWeb ? 'web' : Platform.operatingSystem,
      });

      if (mounted) {
        Navigator.pop(context);
        _showSnackBar('Admin document uploaded successfully');
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context);
        _showSnackBar('Error uploading admin document: $e');
      }
    } finally {
      if (mounted) {
        setState(() => _uploadProgress = null);
      }
    }
  }

  Future<void> _deleteAdminDocument(String docId, String fileName) async {
    if (!_isAdmin) {
      _showSnackBar('Only admins can delete admin documents');
      return;
    }

    if (!mounted) return;
    final bool? confirmDelete = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete Admin Document', style: GoogleFonts.poppins(fontWeight: FontWeight.bold)),
        content: Text(
          'Are you sure you want to delete "$fileName"? This action cannot be undone.',
          style: GoogleFonts.poppins(),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Cancel', style: GoogleFonts.poppins()),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red[700]),
            child: Text('Delete', style: GoogleFonts.poppins(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirmDelete != true) return;

    try {
      await FirebaseFirestore.instance.collection('BillingData').doc(docId).delete();
      if (mounted) _showSnackBar('Admin document deleted successfully');
    } catch (e) {
      if (mounted) _showSnackBar('Error deleting admin document: $e');
    }
  }

  Future<void> _uploadDocument() async {
    if (!_canUpload) {
      if (mounted) _showSnackBar('You do not have permission to upload billing documents');
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
                backgroundColor: Colors.green[800],
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
      _showUploadDialog(fileName);

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
        'isAdminDocument': false,
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

  void _showUploadDialog(String fileName) {
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
                valueColor: const AlwaysStoppedAnimation<Color>(Colors.green),
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
  }

  Future<void> _viewDocument(String url, String fileName, String docId, {bool isAdminDocument = false}) async {
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

    final isPdf = fileName.toLowerCase().endsWith('.pdf');
    final isDocx = fileName.toLowerCase().endsWith('.doc') || fileName.toLowerCase().endsWith('.docx');
    final isExcel = fileName.toLowerCase().endsWith('.xls') || fileName.toLowerCase().endsWith('.xlsx');

    try {
      if (mounted) {
        setState(() {
          _hasViewedDocument = true;
          _currentViewingDocId = docId;
        });
      }

      logger.i('Viewing document: $fileName, url: $url, isAdmin: $isAdminDocument');

      if (isAdminDocument) {
        if (Platform.isAndroid || Platform.isIOS) {
          if (isPdf) {
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
              throw 'Failed to download PDF for viewing';
            }
          } else if (isDocx || isExcel) {
            final uri = Uri.parse(url);
            if (await canLaunchUrl(uri)) {
              await launchUrl(uri, mode: LaunchMode.externalApplication);
              if (mounted) Navigator.pop(context);
            } else {
              throw 'No app available to view $fileName';
            }
          } else {
            throw 'Viewing is only supported for PDF, DOCX, and Excel files on mobile';
          }
        } else if (kIsWeb || Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
          final uri = Uri.parse(url);
          if (await canLaunchUrl(uri)) {
            await launchUrl(uri, mode: LaunchMode.inAppWebView);
            if (mounted) Navigator.pop(context);
          } else {
            throw 'Could not open $fileName in browser';
          }
        }
      } else {
        if (kIsWeb || Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
          if (mounted) Navigator.pop(context);
          final uri = Uri.parse(url);
          if (await canLaunchUrl(uri)) {
            await launchUrl(uri, mode: LaunchMode.externalApplication);
          } else {
            throw 'Could not open $fileName in browser';
          }
        } else if (Platform.isAndroid || Platform.isIOS) {
          if (isPdf) {
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
              throw 'Failed to download PDF for viewing';
            }
          } else {
            if (mounted) Navigator.pop(context);
            final uri = Uri.parse(url);
            if (await canLaunchUrl(uri)) {
              await launchUrl(uri, mode: LaunchMode.externalApplication);
            } else {
              throw 'Could not open $fileName. No app available to view this file type.';
            }
          }
        }
      }
    } catch (e, stackTrace) {
      logger.e('Error viewing document: $e', stackTrace: stackTrace);
      if (mounted) {
        Navigator.pop(context);
        _showSnackBar(
          isAdminDocument && !isPdf && !isDocx && !isExcel
              ? 'Viewing is only supported for PDF, DOCX, and Excel files'
              : 'Error viewing document: $e',
        );
      }
    }
  }

  Future<void> _downloadDocument(String url, String fileName, {bool isAdminDocument = false}) async {
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
      logger.i('Downloading document: $fileName, url: $url, isAdmin: $isAdminDocument');
      
      if (kIsWeb) {
        final uri = Uri.parse(url);
        if (await canLaunchUrl(uri)) {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
          if (mounted) {
            Navigator.pop(context);
            _showSnackBar('Document downloaded to browser downloads');
          }
        } else {
          throw 'Could not download $fileName in browser';
        }
      } else if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
        final tempDir = await getTemporaryDirectory();
        final filePath = '${tempDir.path}/$fileName';
        await Dio().download(url, filePath);
        final file = File(filePath);
        if (await file.exists()) {
          if (mounted) {
            Navigator.pop(context);
            _showSnackBar('Document downloaded to $filePath');
          }
        } else {
          throw 'Failed to download document';
        }
      } else if (Platform.isAndroid || Platform.isIOS) {
        final downloadsDir = await getDownloadsDirectory();
        if (downloadsDir == null) {
          throw 'Could not access downloads directory';
        }
        final filePath = '${downloadsDir.path}/$fileName';
        await Dio().download(url, filePath);
        final file = File(filePath);
        if (await file.exists()) {
          if (mounted) {
            Navigator.pop(context);
            _showSnackBar('Document downloaded to $filePath');
          }
        } else {
          throw 'Failed to download document';
        }
      }
    } catch (e, stackTrace) {
      logger.e('Error downloading document: $e', stackTrace: stackTrace);
      if (mounted) {
        Navigator.pop(context);
        _showSnackBar('Error downloading document: $e');
      }
    }
  }

  Future<void> _updateBillingStatus(String docId, String newStatus) async {
    if (!_isJVAlmacisUser) {
      if (mounted) _showSnackBar('Only JV Almacis users can update payment status');
      return;
    }

    try {
      await FirebaseFirestore.instance.collection('BillingData').doc(docId).update({
        'status': newStatus,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      if (mounted) _showSnackBar('Payment status updated to $newStatus');
      logger.i('Updated payment status: $docId to $newStatus');
    } catch (e, stackTrace) {
      logger.e('Error updating payment status: $e', stackTrace: stackTrace);
      if (mounted) _showSnackBar('Error updating payment status: $e');
    }
  }

  Future<void> _updateApprovalStatus(String docId, String approvalStatus, String? notes) async {
    if (!_isAdminClient) {
      if (mounted) _showSnackBar('Only client admins can update approval status');
      return;
    }

    if (!_hasViewedDocument || _currentViewingDocId != docId) {
      if (mounted) _showSnackBar('Please view the document first before updating approval status');
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
      if (mounted) _showSnackBar('Approval status updated to $approvalStatus');
      logger.i('Updated approval status: $docId to $approvalStatus');
    } catch (e, stackTrace) {
      logger.e('Error updating approval status: $e', stackTrace: stackTrace);
      if (mounted) _showSnackBar('Error updating approval status: $e');
    }
  }

  Future<void> _deleteDocument(String docId, String fileName) async {
    if (!_isJVAlmacisUser) {
      if (mounted) _showSnackBar('Only JV Almacis users can delete documents');
      return;
    }

    if (!mounted) return;
    final bool? confirmDelete = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete Document', style: GoogleFonts.poppins(fontWeight: FontWeight.bold)),
        content: Text(
          'Are you sure you want to delete "$fileName"? This action cannot be undone.',
          style: GoogleFonts.poppins(),
        ),
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

    if (confirmDelete != true) return;

    try {
      await FirebaseFirestore.instance.collection('BillingData').doc(docId).delete();
      if (mounted) _showSnackBar('Document deleted successfully');
      logger.i('Deleted billing document: $docId');
    } catch (e, stackTrace) {
      logger.e('Error deleting billing document: $e', stackTrace: stackTrace);
      if (mounted) _showSnackBar('Error deleting document: $e');
    }
  }

  void _showSnackBar(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message, style: GoogleFonts.poppins())),
      );
    }
  }

  Color _getApprovalStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'approved':
        return Colors.green.shade600;
      case 'review':
        return Colors.orange.shade600;
      case 'pending':
        return Colors.blue.shade600;
      default:
        return Colors.grey.shade600;
    }
  }

  Color _getPaymentStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'paid':
        return Colors.green.shade600;
      case 'pending':
        return Colors.orange.shade600;
      default:
        return Colors.grey.shade600;
    }
  }

  String _getNormalizedApprovalStatus(BillingData billing) {
    if (billing.approvalStatus.toLowerCase() == 'declined') {
      return 'review';
    }
    return billing.approvalStatus;
  }

  IconData _getFileIcon(String fileName) {
    final extension = fileName.toLowerCase().split('.').last;
    switch (extension) {
      case 'pdf':
        return Icons.picture_as_pdf;
      case 'doc':
      case 'docx':
        return Icons.description;
      case 'xls':
      case 'xlsx':
        return Icons.table_chart;
      case 'pptx':
        return Icons.slideshow;
      default:
        return Icons.insert_drive_file;
    }
  }

  Color _getFileIconColor(String fileName) {
    final extension = fileName.toLowerCase().split('.').last;
    switch (extension) {
      case 'pdf':
        return Colors.red[600]!;
      case 'doc':
      case 'docx':
        return Colors.blue[600]!;
      case 'xls':
      case 'xlsx':
        return Colors.green[600]!;
      case 'pptx':
        return Colors.orange[600]!;
      default:
        return Colors.grey[600]!;
    }
  }

  @override
  Widget build(BuildContext context) {
    return ResponsiveScreenWrapper(
      title: 'Billing',
      facilityId: widget.facilityId,
      currentRole: _currentRole,
      organization: _organization,
      floatingActionButton: _canUpload
          ? FloatingActionButton.extended(
              onPressed: () => setState(() => _showForm = !_showForm),
              backgroundColor: Colors.green[800],
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
    final isTablet = screenWidth > 600 && screenWidth <= 900;
    final padding = isMobile ? 16.0 : isTablet ? 24.0 : 32.0;
    final fontSizeTitle = isMobile ? 20.0 : isTablet ? 24.0 : 28.0;
    final fontSizeSubtitle = isMobile ? 14.0 : isTablet ? 16.0 : 18.0;

    return SingleChildScrollView(
      padding: EdgeInsets.all(padding),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildAdminDocumentSection(padding, fontSizeTitle, fontSizeSubtitle),
          
          if (_canUpload && _showForm) _buildUploadForm(padding, fontSizeTitle, fontSizeSubtitle),
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
                .where('isAdminDocument', isEqualTo: false)
                .orderBy('uploadedAt', descending: true)
                .snapshots(),
            builder: (context, snapshot) {
              if (!mounted) return const SizedBox.shrink();
              
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
                        if (_canUpload) ...[
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
              return _buildBillingTable(docs, isMobile, fontSizeSubtitle);
            },
          ),
        ],
      ),
    );
  }

  Widget _buildAdminDocumentSection(double padding, double fontSizeTitle, double fontSizeSubtitle) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('BillingData')
          .where('facilityId', isEqualTo: widget.facilityId)
          .where('isAdminDocument', isEqualTo: true)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError || snapshot.connectionState == ConnectionState.waiting) {
          return const SizedBox.shrink();
        }
        
        final docs = snapshot.data?.docs ?? [];
        final hasAdminDoc = docs.isNotEmpty;
        
        if (!hasAdminDoc && !_isAdmin) {
          return const SizedBox.shrink();
        }
        
        return Column(
          children: [
            Card(
              elevation: 4,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              color: Colors.blue[50],
              child: Padding(
                padding: EdgeInsets.all(padding),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (hasAdminDoc) 
                      _buildExistingAdminDocument(docs.first, fontSizeSubtitle)
                    else if (_isAdmin)
                      _buildUploadAdminDocumentButton(),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
          ],
        );
      },
    );
  }

  Widget _buildExistingAdminDocument(QueryDocumentSnapshot doc, double fontSizeSubtitle) {
    final billing = BillingData.fromSnapshot(doc);
    
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: _getFileIconColor(billing.fileName).withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(
            _getFileIcon(billing.fileName),
            color: _getFileIconColor(billing.fileName),
            size: 32,
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                billing.fileName,
                style: GoogleFonts.poppins(
                  fontWeight: FontWeight.w600,
                  fontSize: fontSizeSubtitle,
                  color: Colors.blueGrey[900],
                ),
              ),
              if (billing.uploadedAt != null)
                Text(
                  'Uploaded: ${DateFormat('MMM dd, yyyy').format(billing.uploadedAt!)}',
                  style: GoogleFonts.poppins(
                    fontSize: fontSizeSubtitle - 2,
                    color: Colors.blueGrey[600],
                  ),
                ),
            ],
          ),
        ),
        PopupMenuButton<String>(
          onSelected: (value) {
            switch (value) {
              case 'view':
                _viewDocument(billing.downloadUrl, billing.fileName, billing.id, isAdminDocument: false); 
                break;
              case 'download':
                _downloadDocument(billing.downloadUrl, billing.fileName, isAdminDocument: true); 
                break;
              case 'update':
                if (_isAdmin) _uploadAdminDocument();
                break;
              case 'delete':
                if (_isAdmin) _deleteAdminDocument(billing.id, billing.fileName);
                break;
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
            if (_isAdmin) ...[
              PopupMenuItem(
                value: 'update',
                child: Row(
                  children: [
                    Icon(Icons.update, color: Colors.orange[700], size: 20),
                    const SizedBox(width: 8),
                    Text('Update', style: GoogleFonts.poppins()),
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
          ],
          icon: Icon(Icons.more_vert, color: Colors.blueGrey[600]),
        ),
      ],
    );
  }

  Widget _buildUploadAdminDocumentButton() {
    return Center(
      child: Column(
        children: [
          Icon(
            Icons.cloud_upload,
            size: 48,
            color: Colors.blueGrey[400],
          ),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: _uploadAdminDocument,
            icon: const Icon(Icons.upload_file, color: Colors.white),
            label: Text(
              'Upload Admin Billing Doc',
              style: GoogleFonts.poppins(
                color: Colors.white,
                fontWeight: FontWeight.w600,
              ),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green[800],
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              elevation: 2,
            ),
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

  Widget _buildBillingTable(List<QueryDocumentSnapshot> docs, bool isMobile, double fontSize) {
    final billingDocs = docs.map((doc) => BillingData.fromSnapshot(doc)).toList();
    
    if (isMobile) {
      return _buildMobileBillingList(billingDocs, fontSize);
    } else {
      return _buildDesktopBillingTable(billingDocs, fontSize);
    }
  }

  Widget _buildMobileBillingList(List<BillingData> billingDocs, double fontSize) {
    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: billingDocs.length,
      itemBuilder: (context, index) {
        final billing = billingDocs[index];
        return Card(
          elevation: 2,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          margin: const EdgeInsets.symmetric(vertical: 6),
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.picture_as_pdf,
                      color: Colors.red[600],
                      size: 32,
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
                              fontSize: fontSize - 2,
                              color: Colors.grey[600],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.grey[50],
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.grey[200]!),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Approval Status',
                            style: GoogleFonts.poppins(
                              fontSize: fontSize - 2,
                              fontWeight: FontWeight.w500,
                              color: Colors.blueGrey[700],
                            ),
                          ),
                          _buildStatusChip(
                            _getNormalizedApprovalStatus(billing),
                            _getApprovalStatusColor(_getNormalizedApprovalStatus(billing)),
                            fontSize,
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Payment Status',
                            style: GoogleFonts.poppins(
                              fontSize: fontSize - 2,
                              fontWeight: FontWeight.w500,
                              color: Colors.blueGrey[700],
                            ),
                          ),
                          _buildStatusChip(
                            billing.status,
                            _getPaymentStatusColor(billing.status),
                            fontSize,
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Actions',
                            style: GoogleFonts.poppins(
                              fontSize: fontSize - 2,
                              fontWeight: FontWeight.w500,
                              color: Colors.blueGrey[700],
                            ),
                          ),
                          _buildActionButtons(billing),
                        ],
                      ),
                      if (billing.approvalNotes != null && billing.approvalNotes!.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.blue[50],
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Approval Notes:',
                                style: GoogleFonts.poppins(
                                  fontSize: fontSize - 3,
                                  fontWeight: FontWeight.w500,
                                  color: Colors.blueGrey[700],
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                billing.approvalNotes!,
                                style: GoogleFonts.poppins(
                                  fontSize: fontSize - 3,
                                  color: Colors.blueGrey[600],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildDesktopBillingTable(List<BillingData> billingDocs, double fontSize) {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
              decoration: BoxDecoration(
                color: Colors.blueGrey[50],
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(8),
                  topRight: Radius.circular(8),
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    flex: 4,
                    child: Text(
                      'Document',
                      style: GoogleFonts.poppins(
                        fontWeight: FontWeight.bold,
                        fontSize: fontSize,
                        color: Colors.blueGrey[800],
                      ),
                    ),
                  ),
                  Expanded(
                    flex: 2,
                    child: Text(
                      'Approval Status',
                      style: GoogleFonts.poppins(
                        fontWeight: FontWeight.bold,
                        fontSize: fontSize,
                        color: Colors.blueGrey[800],
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                  Expanded(
                    flex: 2,
                    child: Text(
                      'Payment Status',
                      style: GoogleFonts.poppins(
                        fontWeight: FontWeight.bold,
                        fontSize: fontSize,
                        color: Colors.blueGrey[800],
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                  Expanded(
                    flex: 1,
                    child: Text(
                      'Actions',
                      style: GoogleFonts.poppins(
                        fontWeight: FontWeight.bold,
                        fontSize: fontSize,
                        color: Colors.blueGrey[800],
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ],
              ),
            ),
            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: billingDocs.length,
              itemBuilder: (context, index) {
                final billing = billingDocs[index];
                final isEven = index % 2 == 0;
                
                return Container(
                  padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                  decoration: BoxDecoration(
                    color: isEven ? Colors.white : Colors.grey[50],
                    border: Border(
                      bottom: BorderSide(
                        color: Colors.grey[200]!,
                        width: 1,
                      ),
                    ),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        flex: 4,
                        child: Row(
                          children: [
                            Icon(
                              Icons.picture_as_pdf,
                              color: Colors.red[600],
                              size: 24,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    billing.title,
                                    style: GoogleFonts.poppins(
                                      fontWeight: FontWeight.w600,
                                      fontSize: fontSize - 1,
                                      color: Colors.blueGrey[900],
                                    ),
                                  ),
                                  Text(
                                    'Uploaded: ${billing.uploadedAt != null ? DateFormat('MMM dd, yyyy').format(billing.uploadedAt!) : 'Unknown'}',
                                    style: GoogleFonts.poppins(
                                      fontSize: fontSize - 3,
                                      color: Colors.grey[600],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      Expanded(
                        flex: 2,
                        child: Center(
                          child: _buildStatusChip(
                            _getNormalizedApprovalStatus(billing),
                            _getApprovalStatusColor(_getNormalizedApprovalStatus(billing)),
                            fontSize,
                          ),
                        ),
                      ),
                      Expanded(
                        flex: 2,
                        child: Center(
                          child: _buildStatusChip(
                            billing.status,
                            _getPaymentStatusColor(billing.status),
                            fontSize,
                          ),
                        ),
                      ),
                      Expanded(
                        flex: 1,
                        child: Center(
                          child: _buildActionButtons(billing),
                        ),
                      ),
                    ],
                  ),
                );
              },
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
        labelText: 'Document Title (Optional)',
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: Colors.grey[400] ?? Colors.grey),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: Colors.green[600]!, width: 2),
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
        backgroundColor: Colors.green[800],
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        elevation: 4,
      ),
    );
  }

  Widget _buildStatusChip(String status, Color color, double fontSize) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Text(
        status.toUpperCase(),
        style: GoogleFonts.poppins(
          color: Colors.white,
          fontSize: fontSize - 4,
          fontWeight: FontWeight.bold,
        ),
        textAlign: TextAlign.center,
      ),
    );
  }

  Widget _buildActionButtons(BillingData billing) {
    List<PopupMenuEntry<String>> menuItems = [];

    menuItems.addAll([
      PopupMenuItem(
        value: 'view',
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4.0, horizontal: 8.0),
          child: Row(
            children: [
              Icon(Icons.visibility, color: Colors.blue[700], size: 20),
              const SizedBox(width: 12),
              Text('View', style: GoogleFonts.poppins()),
            ],
          ),
        ),
      ),
      PopupMenuItem(
        value: 'download',
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4.0, horizontal: 8.0),
          child: Row(
            children: [
              Icon(Icons.download, color: Colors.green[700], size: 20),
              const SizedBox(width: 12),
              Text('Download', style: GoogleFonts.poppins()),
            ],
          ),
        ),
      ),
    ]);

    if (_isAdminClient) {
      final canApprove = _hasViewedDocument && _currentViewingDocId == billing.id;
      final currentApprovalStatus = _getNormalizedApprovalStatus(billing).toLowerCase();

      logger.i('Building action buttons for client admin: canApprove=$canApprove, currentStatus=$currentApprovalStatus, hasViewed=$_hasViewedDocument, currentViewingId=$_currentViewingDocId, billingId=${billing.id}');

      if (currentApprovalStatus == 'approved') {
        menuItems.add(
          PopupMenuItem(
            value: 'review',
            enabled: canApprove,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4.0, horizontal: 8.0),
              child: Row(
                children: [
                  Icon(
                    Icons.rate_review,
                    color: canApprove ? Colors.orange[700] : Colors.grey,
                    size: 20,
                  ),
                  const SizedBox(width: 12),
                  Text(
                    'Review',
                    style: GoogleFonts.poppins(
                      color: canApprove ? Colors.black : Colors.grey,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      } else {
        menuItems.add(
          PopupMenuItem(
            value: 'approve',
            enabled: canApprove,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4.0, horizontal: 8.0),
              child: Row(
                children: [
                  Icon(
                    Icons.check_circle,
                    color: canApprove ? Colors.green[700] : Colors.grey,
                    size: 20,
                  ),
                  const SizedBox(width: 12),
                  Text(
                    'Approve',
                    style: GoogleFonts.poppins(
                      color: canApprove ? Colors.black : Colors.grey,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      }
    }

    if (_isJVAlmacisUser) {
      final currentPaymentStatus = billing.status.toLowerCase();

      if (currentPaymentStatus == 'paid') {
        menuItems.add(
          PopupMenuItem(
            value: 'mark_pending',
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4.0, horizontal: 8.0),
              child: Row(
                children: [
                  Icon(Icons.pending, color: Colors.orange[700], size: 20),
                  const SizedBox(width: 12),
                  Text('Mark as Pending', style: GoogleFonts.poppins()),
                ],
              ),
            ),
          ),
        );
      } else {
        menuItems.add(
          PopupMenuItem(
            value: 'mark_paid',
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4.0, horizontal: 8.0),
              child: Row(
                children: [
                  Icon(Icons.check_circle, color: Colors.green[700], size: 20),
                  const SizedBox(width: 12),
                  Text('Mark as Paid', style: GoogleFonts.poppins()),
                ],
              ),
            ),
          ),
        );
      }

      menuItems.add(
        PopupMenuItem(
          value: 'delete',
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4.0, horizontal: 8.0),
            child: Row(
              children: [
                Icon(Icons.delete, color: Colors.red[700], size: 20),
                const SizedBox(width: 12),
                Text('Delete', style: GoogleFonts.poppins(color: Colors.red[700])),
              ],
            ),
          ),
        ),
      );
    }

    return PopupMenuButton<String>(
      onSelected: (value) {
        switch (value) {
          case 'view':
            _viewDocument(billing.downloadUrl, billing.fileName, billing.id);
            break;
          case 'download':
            _downloadDocument(billing.downloadUrl, billing.fileName, isAdminDocument: false);
            break;
          case 'approve':
            _updateApprovalStatus(billing.id, 'approved', null);
            break;
          case 'review':
            _showReviewDialog(billing.id);
            break;
          case 'mark_paid':
            _updateBillingStatus(billing.id, 'paid');
            break;
          case 'mark_pending':
            _updateBillingStatus(billing.id, 'pending');
            break;
          case 'delete':
            _deleteDocument(billing.id, billing.fileName);
            break;
        }
      },
      itemBuilder: (context) => menuItems,
      icon: const Icon(Icons.more_vert, color: Colors.blueGrey),
      padding: const EdgeInsets.all(8.0),
    );
  }

  void _showReviewDialog(String docId) {
    final notesController = TextEditingController();
    if (!mounted) return;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Review Document', style: GoogleFonts.poppins(fontWeight: FontWeight.bold)),
        content: TextFormField(
          controller: notesController,
          decoration: InputDecoration(
            labelText: 'Review notes (optional)',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
            labelStyle: GoogleFonts.poppins(color: Colors.grey[600]),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: Colors.green[600]!, width: 2),
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
              _updateApprovalStatus(docId, 'review', notesController.text.trim());
              if (mounted) Navigator.pop(context);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orange[700],
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: Text('Review', style: GoogleFonts.poppins(color: Colors.white)),
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