import 'dart:convert';
import 'dart:io';

import 'package:alisthelper/provider/alist_provider.dart';
import 'package:alisthelper/provider/persistence_provider.dart';
import 'package:alisthelper/utils/server_executable.dart';
import 'package:archive/archive.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Optional real-binary smoke tests. All data and listeners are isolated from
/// the user's installation. Set OPENLIST_TEST_BINARY to run these on Windows.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // These process tests intentionally use a local HTTP server, rather than
  // widget tests' default HTTP client that returns a synthetic 400 response.
  HttpOverrides.global = null;
  final binaryPath = Platform.environment['OPENLIST_TEST_BINARY'];
  final enabled = Platform.isWindows && binaryPath != null;

  group(
    'OpenList process and update integration',
    () {
      late Directory directory;
      late HttpServer downloads;
      late ProviderContainer container;
      late AlistNotifier notifier;
      late int serverPort;
      late List<int> archive;

      setUpAll(() {
        archive = ZipEncoder().encode(
          Archive()..addFile(
            ArchiveFile.bytes(
              'openlist.exe',
              File(binaryPath!).readAsBytesSync(),
            ),
          ),
        );
      });

      setUp(() async {
        directory = Directory.systemTemp.createTempSync(
          'alisthelper-openlist-',
        );
        final data = Directory('${directory.path}/data')..createSync();
        final socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
        serverPort = socket.port;
        await socket.close();
        File('${data.path}/config.json').writeAsStringSync(
          jsonEncode({
            'scheme': {
              'address': '127.0.0.1',
              'http_port': serverPort,
              'https_port': -1,
            },
          }),
        );
        downloads = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        downloads.listen((request) async {
          request.response.add(archive);
          await request.response.close();
        });
        SharedPreferences.setMockInitialValues({
          'ah_working_directory': directory.path,
          'ah_alist_args': ['server', '--data', data.path, '--log-std'],
          'ah_locale': 'en',
        });
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(
              const MethodChannel('tray_manager'),
              (_) async => null,
            );
        final persistence = await PersistenceService.initialize();
        container = ProviderContainer(
          overrides: [persistenceProvider.overrideWithValue(persistence)],
        );
        notifier = container.read(alistProvider.notifier);
      });

      tearDown(() async {
        await notifier.endAlist();
        container.dispose();
        await downloads.close(force: true);
        directory.deleteSync(recursive: true);
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(
              const MethodChannel('tray_manager'),
              null,
            );
      });

      Future<void> expectServing() async {
        final deadline = DateTime.now().add(const Duration(seconds: 20));
        while (!container.read(alistProvider).isRunning) {
          if (DateTime.now().isAfter(deadline)) {
            fail('OpenList did not report a listening server');
          }
          await Future<void>.delayed(const Duration(milliseconds: 50));
        }
        expect(
          container.read(alistProvider).url,
          'http://localhost:$serverPort',
        );
        final client = HttpClient();
        try {
          final request = await client.getUrl(
            Uri.parse('http://127.0.0.1:$serverPort/api/public/settings'),
          );
          final response = await request.close();
          expect(response.statusCode, 200);
          await response.drain<void>();
        } finally {
          client.close(force: true);
        }
      }

      Future<void> expectStopped() async {
        await notifier.endAlist();
        expect(container.read(alistProvider).isRunning, isFalse);
        // The port is available as soon as endAlist completes.
        final socket = await ServerSocket.bind(
          InternetAddress.loopbackIPv4,
          serverPort,
        );
        await socket.close();
      }

      test(
        'fresh install, version, start/stop and in-place OpenList upgrade',
        () async {
          final url = 'http://127.0.0.1:${downloads.port}/openlist.zip';
          await notifier.installAlist(url);
          final version = container.read(alistProvider).currentVersion;
          expect(version, isNot('v1.0.0'));
          expect(
            ServerExecutable.require(directory.path).uri.pathSegments.last,
            'openlist.exe',
          );
          expect(File('${directory.path}/alist.exe').existsSync(), isFalse);
          await notifier.startAlist();
          await expectServing();
          await notifier.upgradeAlist(url);
          await expectServing();
          expect(
            File('${directory.path}/.old/openlist-$version.exe').existsSync(),
            isTrue,
          );
          expect(File('${directory.path}/openlist.exe').existsSync(), isTrue);
          expect(File('${directory.path}/alist.exe').existsSync(), isFalse);
          await expectStopped();
        },
        timeout: const Timeout(Duration(minutes: 2)),
      );

      test(
        'migrates an existing renamed binary to its original OpenList name',
        () async {
          File(binaryPath!).copySync('${directory.path}/alist.exe');
          await notifier.getAlistCurrentVersion(addToOutput: false);
          final version = container.read(alistProvider).currentVersion;
          await notifier.startAlist();
          await expectServing();
          await notifier.upgradeAlist(
            'http://127.0.0.1:${downloads.port}/openlist.zip',
          );
          await expectServing();
          expect(
            File('${directory.path}/.old/alist-$version.exe').existsSync(),
            isTrue,
          );
          expect(File('${directory.path}/openlist.exe').existsSync(), isTrue);
          expect(File('${directory.path}/alist.exe').existsSync(), isFalse);
          await expectStopped();
        },
        timeout: const Timeout(Duration(minutes: 2)),
      );
    },
    skip: enabled ? false : 'Set OPENLIST_TEST_BINARY on Windows to run',
  );
}
