import 'dart:io';

import 'package:alisthelper/utils/native/file_helper.dart';
import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('extracts OpenList and releases the ZIP before returning', () {
    final directory = Directory.systemTemp.createTempSync('alisthelper-zip-');
    try {
      final zip = File('${directory.path}/release.zip')
        ..writeAsBytesSync(
          ZipEncoder().encode(
            Archive()..addFile(ArchiveFile.bytes('openlist.exe', [1, 2, 3, 4])),
          ),
        );
      FileHelper.unzipFile(zip.path, directory.path);
      zip.deleteSync();
      expect(File('${directory.path}/openlist.exe').readAsBytesSync(), [
        1,
        2,
        3,
        4,
      ]);
      expect(File('${directory.path}/alist.exe').existsSync(), isFalse);
    } finally {
      directory.deleteSync(recursive: true);
    }
  });
}
