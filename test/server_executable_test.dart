import 'dart:io';

import 'package:alisthelper/utils/server_executable.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory directory;

  setUp(() {
    directory = Directory.systemTemp.createTempSync('alisthelper-executable-');
  });

  tearDown(() {
    directory.deleteSync(recursive: true);
  });

  for (final windows in [true, false]) {
    final suffix = windows ? '.exe' : '';
    final platform = windows ? 'Windows' : 'Unix';

    group(platform, () {
      test('accepts the original OpenList filename', () {
        final executable = File('${directory.path}/openlist$suffix')
          ..writeAsStringSync('openlist');
        expect(
          ServerExecutable.find(directory.path, windows: windows)?.path,
          executable.path,
        );
        expect(executable.existsSync(), isTrue);
      });

      test('keeps existing AList installations usable', () {
        final executable = File('${directory.path}/alist$suffix')
          ..writeAsStringSync('alist');
        expect(
          ServerExecutable.find(directory.path, windows: windows)?.path,
          executable.path,
        );
      });

      test('prefers OpenList when both are present', () {
        File('${directory.path}/alist$suffix').writeAsStringSync('alist');
        final openlist = File('${directory.path}/openlist$suffix')
          ..writeAsStringSync('openlist');
        expect(
          ServerExecutable.find(directory.path, windows: windows)?.path,
          openlist.path,
        );
      });

      test('rejects similarly named files and directories', () {
        File('${directory.path}/not-openlist$suffix').writeAsStringSync('x');
        Directory('${directory.path}/openlist$suffix').createSync();
        expect(ServerExecutable.find(directory.path, windows: windows), isNull);
      });

      test('backs up using the original binary name', () {
        final file = File('${directory.path}/openlist$suffix');
        expect(
          ServerExecutable.backupFile(file, 'v4.2.0').path,
          '${file.parent.path}/.old/openlist-v4.2.0$suffix',
        );
      });
    });
  }

  test('reports a missing server instead of using the current directory', () {
    expect(ServerExecutable.find(''), isNull);
    expect(
      () => ServerExecutable.require(directory.path),
      throwsA(isA<FileSystemException>()),
    );
  });

  test('reads OpenList version without confusing WebVersion', () {
    final info = ServerExecutable.parseVersion(
      'Built At: 2026-04-08 14:15:23 +0000\r\n'
      'Go Version: go1.25.1 windows/amd64\r\n'
      'Author: The OpenList Projects Contributors\r\n'
      'Commit ID: e11b8a82\r\n'
      'Version: v4.2.0\r\n'
      'WebVersion: v4.2.0\r\n',
    );
    expect(info.version, 'v4.2.0');
    expect(info.architecture, 'amd64');
  });

  test('reads AList version and non-Windows architectures', () {
    final info = ServerExecutable.parseVersion(
      'Go Version: go1.22.1 darwin/arm64\n'
      'Version: v3.35.0\n'
      'WebVersion: 3.35.0\n',
    );
    expect(info.version, 'v3.35.0');
    expect(info.architecture, 'arm64');
  });

  test('reports malformed version output', () {
    expect(
      () => ServerExecutable.parseVersion('WebVersion: v4.2.0'),
      throwsFormatException,
    );
  });
}
