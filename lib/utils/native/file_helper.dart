import 'dart:io';

import 'package:archive/archive_io.dart';

class FileHelper {
  static void unzipFile(String targetArchiveFile, String outputFolder) {
    final inputStream = InputFileStream(targetArchiveFile);
    try {
      final archive = ZipDecoder().decodeStream(inputStream);
      for (var file in archive.files) {
        if (file.isFile) {
          final outputStream = OutputFileStream('$outputFolder/${file.name}');
          try {
            file.writeContent(outputStream);
          } finally {
            outputStream.closeSync();
          }
        }
      }
    } finally {
      // Installation deletes the ZIP immediately after this synchronous call.
      inputStream.closeSync();
    }
  }

  static void extractRclone(String targetArchiveFile, String outputFolder) {
    final inputStream = InputFileStream(targetArchiveFile);
    final executableName = Platform.isWindows ? 'rclone.exe' : 'rclone';
    try {
      final archive = ZipDecoder().decodeStream(inputStream);
      for (var file in archive.files) {
        if (file.isFile && file.name.split('/').last == executableName) {
          final outputStream = OutputFileStream(
            '$outputFolder/$executableName',
          );
          try {
            file.writeContent(outputStream);
          } finally {
            outputStream.closeSync();
          }
        }
      }
    } finally {
      inputStream.closeSync();
    }
  }
}
