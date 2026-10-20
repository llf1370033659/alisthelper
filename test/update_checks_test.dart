import 'dart:io';

import 'package:alisthelper/provider/alist_provider.dart';
import 'package:alisthelper/provider/persistence_provider.dart';
import 'package:alisthelper/provider/updater_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = null;
  final directory = Platform.environment['HELPER_LIVE_CHECK_DIRECTORY'];

  test(
    'installed programs can check official latest releases',
    () async {
      SharedPreferences.setMockInitialValues({
        'ah_working_directory': directory!,
        'ah_rclone_directory': directory,
        'ah_locale': 'en',
      });
      final persistence = await PersistenceService.initialize();
      final container = ProviderContainer(
        overrides: [persistenceProvider.overrideWithValue(persistence)],
      );
      try {
        final openlist = container.read(alistProvider.notifier);
        final rclone = container.read(updaterProvider.notifier);
        await openlist.getAlistCurrentVersion(addToOutput: false);
        await openlist.fetchLatestVersion();
        await rclone.getRcloneCurrentVersion();
        await rclone.fetchLatestVersion();
        final server = container.read(alistProvider);
        final clone = container.read(updaterProvider);
        expect(server.currentVersion, server.latestVersion);
        expect(clone.rcloneCurrentVersion, clone.rcloneLatestVersion);
        expect(server.newReleaseAssets, hasLength(1));
        expect(
          server.newReleaseAssets.single['name'],
          'openlist-windows-amd64.zip',
        );
        expect(clone.rcloneAssets, hasLength(1));
        expect(
          clone.rcloneAssets.single['name'],
          'rclone-${clone.rcloneLatestVersion}-windows-amd64.zip',
        );
      } finally {
        container.dispose();
      }
    },
    skip: directory == null ? 'Set HELPER_LIVE_CHECK_DIRECTORY to run' : false,
  );
}
