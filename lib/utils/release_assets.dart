import 'dart:ffi';

String hostGoArchitecture() =>
    switch (Abi.current().toString().split('_').last) {
      'x64' => 'amd64',
      'ia32' => '386',
      final architecture => architecture,
    };

/// Select the normal ZIP for the installed platform and architecture.
/// Excludes OpenList lite/Windows 7 builds and unrelated rclone archives.
List<Map> compatibleReleaseAssets(
  List assets, {
  required String program,
  required String platform,
  required String architecture,
}) {
  final suffix = '$platform-$architecture.zip';
  return assets.whereType<Map>().where((asset) {
    final name = asset['name'] as String? ?? '';
    if (program == 'openlist') return name == 'openlist-$suffix';
    return name.startsWith('rclone-v') && name.endsWith('-$suffix');
  }).toList();
}
