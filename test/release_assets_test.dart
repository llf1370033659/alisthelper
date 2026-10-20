import 'package:alisthelper/utils/release_assets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'OpenList selects normal Windows ZIP for the installed architecture',
    () {
      final names = [
        'openlist-windows-amd64.zip',
        'openlist-windows-amd64-lite.zip',
        'openlist-windows7-amd64.zip',
        'openlist-windows-arm64.zip',
        'openlist-linux-amd64.tar.gz',
      ];
      final result = compatibleReleaseAssets(
        names.map((name) => {'name': name}).toList(),
        program: 'openlist',
        platform: 'windows',
        architecture: 'amd64',
      );
      expect(result.map((asset) => asset['name']), [
        'openlist-windows-amd64.zip',
      ]);
    },
  );

  test(
    'rclone selects matching ZIP and excludes checksum and other platforms',
    () {
      final names = [
        'rclone-v1.75.2-windows-amd64.zip',
        'rclone-v1.75.2-windows-arm64.zip',
        'rclone-v1.75.2-linux-amd64.zip',
        'SHA256SUMS',
      ];
      final result = compatibleReleaseAssets(
        names.map((name) => {'name': name}).toList(),
        program: 'rclone',
        platform: 'windows',
        architecture: 'arm64',
      );
      expect(result.map((asset) => asset['name']), [
        'rclone-v1.75.2-windows-arm64.zip',
      ]);
    },
  );
}
