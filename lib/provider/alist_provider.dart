import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:alisthelper/model/alist_state.dart';
import 'package:alisthelper/utils/native/tray_helper.dart';
import 'package:alisthelper/utils/native/file_helper.dart';
import 'package:dio/dio.dart';
import 'package:http/http.dart' as http;

import 'package:alisthelper/provider/settings_provider.dart';
import 'package:alisthelper/utils/textutils.dart';
import 'package:alisthelper/utils/server_executable.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logger/logger.dart';

final alistProvider = NotifierProvider<AlistNotifier, AlistState>(
  AlistNotifier.new,
);

class AlistNotifier extends Notifier<AlistState> {
  List<String> stdOut = [];
  Logger logger = Logger();
  Process? _serverProcess;

  @override
  AlistState build() {
    return AlistState(
      workDir: ref.read(settingsProvider.select((s) => s.workingDirectory)),
      alistArgs: ref.read(settingsProvider.select((s) => s.alistArgs)),
      proxy: ref.read(settingsProvider.select((s) => s.proxy ?? '')),
    );
  }

  Future<void> setWorkDir(String workDir) async {
    await endAlist();
    ref.read(settingsProvider.notifier).setWorkingDirectory(workDir);
    state = state.copyWith(workDir: workDir);
  }

  Future<void> setAlistArgs(List<String> args) async {
    await endAlist();
    ref.read(settingsProvider.notifier).setAlistArgs(args);
    state = state.copyWith(alistArgs: args);
  }

  Future<void> setProxy(String proxy) async {
    ref.read(settingsProvider.notifier).setProxy(proxy);
    state = state.copyWith(proxy: proxy);
  }

  void addOutput(String text) {
    // Split the text into lines to handle multi-line log chunks.
    final lines = text.split('\n');
    for (final line in lines) {
      // Process only non-empty lines.
      if (line.isNotEmpty) {
        stdOut.add(line);
        // Check for the server start message in any line.
        if (line.contains('start HTTP server @')) {
          checkState(line);
        }
      }
    }
    // Update the state with the new output list.
    state = state.copyWith(output: stdOut);
  }

  void checkState(String text) {
    if (text.contains('FATA')) {
      text = text.split('FATA')[0].trim();
    }
    String port = text.split('@')[1].trim().split(':')[1].trim();
    String url = 'http://localhost:$port';
    state = state.copyWith(isRunning: true, url: url);
  }

  Future<void> startAlist() async {
    if (_serverProcess != null) return;
    final executable = ServerExecutable.require(state.workDir);
    final Map<String, String> envVars = Map.from(Platform.environment);
    if (state.proxy != '') {
      envVars['http_proxy'] = state.proxy;
      envVars['https_proxy'] = state.proxy;
      addOutput('Proxy: ${state.proxy}');
    }
    final process = await Process.start(
      executable.path,
      state.alistArgs,
      workingDirectory: state.workDir,
      environment: envVars,
    );
    _serverProcess = process;
    await changeTray(true);

    process.exitCode.then((_) async {
      if (identical(_serverProcess, process)) {
        _serverProcess = null;
        state = state.copyWith(isRunning: false);
        await changeTray(false);
      }
    });

    process.stdout.listen((data) {
      String text = TextUtils.stdDecode(data, false);
      addOutput(text);
    });
    process.stderr.listen((data) {
      String text = TextUtils.stdDecode(data, false);
      addOutput(text);
    });
  }

  Future<void> endAlist() async {
    // Stop the process this helper started, regardless of its executable name.
    final process = _serverProcess;
    _serverProcess = null;
    if (process != null) {
      process.kill();
      await process.exitCode;
    }
    state = state.copyWith(isRunning: false);
    await changeTray(false);
  }

  //get alist admin
  Future<void> genRandomPwd() async {
    final executable = ServerExecutable.require(state.workDir);
    final alistAdmin = await Process.start(executable.path, [
      'admin',
      'random',
    ], workingDirectory: state.workDir);
    alistAdmin.stderr.listen((data) {
      String text = TextUtils.stdDecode(data, false);
      if (text.contains('password:')) {
        String password = text.split('password:')[1].trim();
        addOutput(password);
      }
      addOutput(text);
    });
  }

  //get alist version and architecture
  Future<void> getAlistCurrentVersion({required bool addToOutput}) async {
    try {
      final executable = ServerExecutable.require(state.workDir);
      final result = await Process.run(executable.path, [
        'version',
      ], workingDirectory: state.workDir);
      if (result.exitCode != 0) {
        throw ProcessException(
          executable.path,
          ['version'],
          result.stderr.toString(),
          result.exitCode,
        );
      }
      final text = TextUtils.removeEscapeSequences(
        '${result.stdout}\n${result.stderr}',
      );
      final info = ServerExecutable.parseVersion(text);
      state = state.copyWith(
        currentVersion: info.version,
        alistArchitecture: info.architecture,
      );
      if (addToOutput) addOutput(text);
    } on ProcessException catch (e) {
      logger.e('Error: ${e.message}');
    }
  }

  Future<void> fetchLatestVersion() async {
    final response = await http.get(
      Uri.parse(
        'https://api.github.com/repos/OpenListTeam/OpenList/releases/latest',
      ),
    );
    final json = jsonDecode(response.body) as Map<String, dynamic>;
    try {
      String latest = json['tag_name'];
      List assets = json['assets'];
      String platformKey = Platform.isWindows
          ? 'windows'
          : (Platform.isMacOS ? 'darwin' : 'linux');
      List<Map> assetsForSpecificPlatform = [];
      for (Map asset in assets) {
        if (asset['name'].contains(platformKey)) {
          //remove the asset if it's not for the current platform
          assetsForSpecificPlatform.add(asset);
        }
      }
      // Preventing uninitialized version string
      if (state.currentVersion == "v1.0.0") {
        await getAlistCurrentVersion(addToOutput: false);
      }
      state = state.copyWith(
        latestVersion: latest,
        newReleaseAssets: assetsForSpecificPlatform,
        upgradeStatus: UpgradeStatus.idle,
      );
    } catch (e) {
      throw Exception(
        '$e\nFailed to get latest version when fetching: ${json.toString()}',
      );
    }
  }

  Future<void> installAlist(String downloadLink) async {
    state = state.copyWith(upgradeStatus: UpgradeStatus.installing);
    String targetArchiveFile = '${state.workDir}/alistnew.zip';
    await Dio().download(downloadLink, targetArchiveFile);
    FileHelper.unzipFile(targetArchiveFile, state.workDir);
    await File(targetArchiveFile).delete();
    await getAlistCurrentVersion(addToOutput: false);
    state = state.copyWith(upgradeStatus: UpgradeStatus.complete);
    //startAlist();
  }

  Future<void> upgradeAlist(String downloadLink) async {
    state = state.copyWith(upgradeStatus: UpgradeStatus.installing);
    String targetArchiveFile = '${state.workDir}/alistnew.zip';
    String backupFolder = '${state.workDir}/.old';
    final currentAlist = ServerExecutable.require(state.workDir);
    final backupFile = ServerExecutable.backupFile(
      currentAlist,
      state.currentVersion,
    );

    await Dio().download(downloadLink, targetArchiveFile);
    await endAlist();
    if (!await Directory(backupFolder).exists()) {
      await Directory(backupFolder).create();
    }
    if (await backupFile.exists()) {
      await backupFile.delete();
    }
    await currentAlist.rename(backupFile.path);
    FileHelper.unzipFile('${state.workDir}/alistnew.zip', state.workDir);
    await File(targetArchiveFile).delete();
    await getAlistCurrentVersion(addToOutput: false);
    state = state.copyWith(upgradeStatus: UpgradeStatus.complete);
    await startAlist();
  }
}
