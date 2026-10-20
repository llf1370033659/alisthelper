import 'dart:convert';
import 'dart:io';
import 'package:alisthelper/model/updater_state.dart';
import 'package:alisthelper/provider/rclone_provider.dart';
import 'package:alisthelper/provider/settings_provider.dart';
import 'package:alisthelper/utils/native/file_helper.dart';
import 'package:alisthelper/utils/textutils.dart';
import 'package:alisthelper/utils/release_assets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dio/dio.dart';
import 'package:http/http.dart' as http;
import 'package:logger/logger.dart';

final updaterProvider = NotifierProvider<UpdaterNotifier, UpdaterState>(
  UpdaterNotifier.new,
);

class UpdaterNotifier extends Notifier<UpdaterState> {
  Dio dio = Dio();
  Logger logger = Logger();
  String _architecture = hostGoArchitecture();

  @override
  UpdaterState build() {
    return UpdaterState(
      rcloneDirectory: ref.watch(settingsProvider).rcloneDirectory,
    );
  }

  Future<void> getRcloneInfo() async {
    try {
      final name = Platform.isWindows ? 'rclone.exe' : 'rclone';
      final result = await Process.run('${state.rcloneDirectory}/$name', [
        'version',
      ], workingDirectory: state.rcloneDirectory);
      if (result.exitCode != 0) {
        throw ProcessException(
          name,
          ['version'],
          result.stderr.toString(),
          result.exitCode,
        );
      }
      _parseVersion(TextUtils.removeEscapeSequences(result.stdout.toString()));
    } on ProcessException catch (e) {
      logger.e('ProcessException: $e');
    }
  }

  void _parseVersion(String output) {
    final versionRegExp = RegExp(r'rclone v([\d.]+)');
    final match = versionRegExp.firstMatch(output);
    if (match != null) {
      final version = 'v${match.group(1)}';
      _architecture =
          RegExp(r'os/arch:\s*(\S+)').firstMatch(output)?.group(1) ??
          hostGoArchitecture();
      state = state.copyWith(rcloneCurrentVersion: version);
    }
  }

  Future<void> getRcloneCurrentVersion() async {
    await getRcloneInfo();
  }

  Future<void> fetchLatestVersion() async {
    final response = await http.get(
      Uri.parse('https://api.github.com/repos/rclone/rclone/releases/latest'),
    );
    final json = jsonDecode(response.body) as Map<String, dynamic>;
    try {
      String latest = json['tag_name'];
      List assets = json['assets'];
      String platformKey = Platform.isWindows
          ? 'windows'
          : (Platform.isMacOS ? 'darwin' : 'linux');
      // Preventing uninitialized version string
      if (state.rcloneCurrentVersion == "v1.0.0") {
        await getRcloneCurrentVersion();
      }
      final assetsForSpecificPlatform = compatibleReleaseAssets(
        assets,
        program: 'rclone',
        platform: platformKey,
        architecture: _architecture,
      );
      state = state.copyWith(
        rcloneLatestVersion: latest,
        rcloneAssets: assetsForSpecificPlatform,
        upgradeStatus: UpgradeStatus.idle,
      );
    } catch (e) {
      throw Exception(
        '$e\nFailed to get latest version when fetching: ${json.toString()}',
      );
    }
  }

  Future<void> installRclone(String downloadLink) async {
    state = state.copyWith(upgradeStatus: UpgradeStatus.installing);
    String targetArchiveFile = '${state.rcloneDirectory}/rclonenew.zip';
    await Dio().download(downloadLink, targetArchiveFile);
    FileHelper.extractRclone(targetArchiveFile, state.rcloneDirectory);
    await File(targetArchiveFile).delete();
    await getRcloneCurrentVersion();
    state = state.copyWith(upgradeStatus: UpgradeStatus.complete);
    //startAlist();
  }

  Future<void> upgradeRclone(String downloadLink) async {
    state = state.copyWith(upgradeStatus: UpgradeStatus.installing);
    String targetArchiveFile = '${state.rcloneDirectory}/rclonenew.zip';
    String backupFolder = '${state.rcloneDirectory}/.old';
    String currentRclone = Platform.isWindows
        ? '${state.rcloneDirectory}/rclone.exe'
        : '${state.rcloneDirectory}/rclone';
    await Dio().download(downloadLink, targetArchiveFile);
    final wasRunning = ref.read(rcloneProvider).isRunning;
    await ref.read(rcloneProvider.notifier).endRclone();
    if (!await Directory(backupFolder).exists()) {
      await Directory(backupFolder).create();
    }
    final suffix = Platform.isWindows ? '.exe' : '';
    final backup = File(
      '$backupFolder/rclone-${state.rcloneCurrentVersion}$suffix',
    );
    if (await backup.exists()) {
      await backup.delete();
    }
    await File(currentRclone).rename(backup.path);
    FileHelper.extractRclone(
      '${state.rcloneDirectory}/rclonenew.zip',
      state.rcloneDirectory,
    );
    await File(targetArchiveFile).delete();
    await getRcloneCurrentVersion();
    state = state.copyWith(upgradeStatus: UpgradeStatus.complete);
    if (wasRunning) await ref.read(rcloneProvider.notifier).startRclone();
  }
}
