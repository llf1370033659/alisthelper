import 'dart:io';

import 'package:alisthelper/provider/persistence_provider.dart';
import 'package:alisthelper/provider/rclone_provider.dart';
import 'package:alisthelper/provider/updater_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = null;
  final zipPath = Platform.environment['RCLONE_TEST_ZIP'];

  test(
    'installs rclone, updates a running direct command and restarts it',
    () async {
      final directory = Directory.systemTemp.createTempSync('helper-rclone-');
      final files = Directory('${directory.path}/files')..createSync();
      File('${files.path}/hello.txt').writeAsStringSync('hello');
      final portReservation = await ServerSocket.bind(
        InternetAddress.loopbackIPv4,
        0,
      );
      final port = portReservation.port;
      await portReservation.close();
      final zip = File(zipPath!).readAsBytesSync();
      final downloads = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      downloads.listen((request) async {
        request.response.add(zip);
        await request.response.close();
      });
      SharedPreferences.setMockInitialValues({
        'ah_rclone_directory': directory.path,
        'ah_rclone_args': [
          'serve',
          'http',
          files.path,
          '--addr',
          '127.0.0.1:$port',
        ],
        'ah_locale': 'en',
      });
      final persistence = await PersistenceService.initialize();
      final container = ProviderContainer(
        overrides: [persistenceProvider.overrideWithValue(persistence)],
      );
      final updater = container.read(updaterProvider.notifier);
      final rclone = container.read(rcloneProvider.notifier);
      Future<void> expectServing() async {
        final deadline = DateTime.now().add(const Duration(seconds: 10));
        while (true) {
          final client = HttpClient();
          try {
            final request = await client.getUrl(
              Uri.parse('http://127.0.0.1:$port/hello.txt'),
            );
            final response = await request.close();
            expect(response.statusCode, 200);
            await response.drain<void>();
            return;
          } on SocketException {
            if (DateTime.now().isAfter(deadline)) rethrow;
            await Future<void>.delayed(const Duration(milliseconds: 50));
          } finally {
            client.close(force: true);
          }
        }
      }

      try {
        final url = 'http://127.0.0.1:${downloads.port}/rclone.zip';
        await updater.installRclone(url);
        final version = container.read(updaterProvider).rcloneCurrentVersion;
        expect(version, isNot('v1.0.0'));
        await rclone.startRclone();
        await expectServing();
        expect(container.read(rcloneProvider).isRunning, isTrue);
        await updater.upgradeRclone(url);
        await expectServing();
        expect(container.read(rcloneProvider).isRunning, isTrue);
        expect(
          File('${directory.path}/.old/rclone-$version.exe').existsSync(),
          isTrue,
        );
        expect(File('${directory.path}/rclonenew.zip').existsSync(), isFalse);
        await rclone.endRclone();
        final socket = await ServerSocket.bind(
          InternetAddress.loopbackIPv4,
          port,
        );
        await socket.close();
      } finally {
        await rclone.endRclone();
        container.dispose();
        await downloads.close(force: true);
        directory.deleteSync(recursive: true);
      }
    },
    skip: Platform.isWindows && zipPath != null
        ? false
        : 'Set RCLONE_TEST_ZIP on Windows to run',
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
