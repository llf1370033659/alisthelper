import 'dart:io';

/// Resolves the server without renaming OpenList binaries to AList.
class ServerExecutable {
  static List<String> names({bool? windows}) => (windows ?? Platform.isWindows)
      ? const ['openlist.exe', 'alist.exe']
      : const ['openlist', 'alist'];

  /// Prefer OpenList when both binaries are present; keep legacy AList usable.
  static File? find(String directory, {bool? windows}) {
    if (directory.isEmpty) return null;
    for (final name in names(windows: windows)) {
      final file = File('$directory/$name');
      if (file.existsSync()) return file;
    }
    return null;
  }

  static File require(String directory) {
    final file = find(directory);
    if (file == null) {
      throw FileSystemException(
        'Could not find ${names().join(" or ")}',
        directory,
      );
    }
    return file;
  }

  static File backupFile(File executable, String version) {
    final name = executable.uri.pathSegments.last;
    final stem = name.endsWith('.exe')
        ? name.substring(0, name.length - 4)
        : name;
    final suffix = name.endsWith('.exe') ? '.exe' : '';
    return File('${executable.parent.path}/.old/$stem-$version$suffix');
  }

  /// Parse complete output, since stdout chunks need not end on line boundaries.
  static ({String version, String architecture}) parseVersion(String output) {
    final version = RegExp(
      r'^Version:\s*(\S+)',
      multiLine: true,
    ).firstMatch(output)?.group(1);
    final architecture = RegExp(
      r'^Go Version:.*\s\S+/(\S+)',
      multiLine: true,
    ).firstMatch(output)?.group(1);
    if (version == null || architecture == null) {
      throw const FormatException('Unrecognized AList/OpenList version output');
    }
    return (version: version, architecture: architecture);
  }
}
