import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:logger/logger.dart';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

class PdfService {
  final Logger _logger = Logger();

  Future<String?> uploadFile({
    required String facilityId,
    required String collection,
    required String title,
    required String category,
    required List<String> allowedExtensions,
  }) async {
    try {
      _logger.i('Picking file for collection: $collection, allowedExtensions: $allowedExtensions');

      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: allowedExtensions,
        allowMultiple: false,
      );
      if (result == null || result.files.isEmpty) {
        _logger.w('No file selected');
        return null;
      }

      final file = result.files.first;
      _logger.i('Uploading file: ${file.name}, bytes: ${file.bytes != null}');

      // Storage path: facilities/{facilityId}/{collection}/{fileName}
      final storagePath = 'facilities/$facilityId/$collection/${DateTime.now().millisecondsSinceEpoch}_${file.name}';
      final storageRef = FirebaseStorage.instance.ref().child(storagePath);

      String url;
      if (kIsWeb) {
        if (file.bytes == null) {
          _logger.e('No bytes available for web upload');
          throw Exception('File data unavailable');
        }
        final uploadTask = await storageRef.putData(
          file.bytes!,
          SettableMetadata(contentType: 'application/pdf'),
        );
        url = await uploadTask.ref.getDownloadURL();
      } else {
        if (file.path == null) {
          _logger.e('No path available for non-web upload');
          throw Exception('File path unavailable');
        }
        final uploadTask = await storageRef.putFile(
          File(file.path!),
          SettableMetadata(contentType: 'application/pdf'),
        );
        url = await uploadTask.ref.getDownloadURL();
      }

      _logger.i('File uploaded to Storage: $url');
      // Use original filename if title is 'OriginalFilename'
      final finalTitle = title == 'OriginalFilename' ? file.name : title;
      await FirebaseFirestore.instance
          .collection('facilities')
          .doc(facilityId)
          .collection(collection)
          .add({
        'title': finalTitle,
        'category': category,
        'fileUrl': url,
        'extension': file.name.split('.').last.toLowerCase(),
        'uploadedAt': Timestamp.now(),
      });

      _logger.i('File metadata saved to Firestore');
      return url;
    } catch (e, stackTrace) {
      _logger.e('Error uploading file: $e', stackTrace: stackTrace);
      rethrow;
    }
  }

  Future<File> downloadPdf(String url) async {
    try {
      _logger.i('Downloading PDF from URL: $url');
      final response = await http.get(Uri.parse(url));
      if (response.statusCode != 200) {
        _logger.e('Failed to download PDF: HTTP ${response.statusCode}');
        throw Exception('Failed to download PDF: HTTP ${response.statusCode}');
      }

      final tempDir = await getTemporaryDirectory();
      final fileName = '${DateTime.now().millisecondsSinceEpoch}.pdf';
      final file = File('${tempDir.path}/$fileName');

      await file.writeAsBytes(response.bodyBytes);
      _logger.i('PDF downloaded and saved to: ${file.path}');
      return file;
    } catch (e, stackTrace) {
      _logger.e('Error downloading PDF: $e', stackTrace: stackTrace);
      rethrow;
    }
  }
}