# OpenList 原文件名适配

基于 Xmarmalade/alisthelper 的 `6d7e1acb86a5c67bcf86d99bc6034f130b1d04c2` 修改。

## 行为

- 工作目录接受 `openlist.exe` 和 `alist.exe`，两者同时存在时优先 OpenList。
- macOS/Linux 同样识别 `openlist` 和 `alist`。
- 启动、版本读取、随机管理员密码命令均使用检测到的可执行文件。
- 停止、托盘退出操作等待 Helper 自己启动的服务进程退出，不再按固定的 `alist.exe` 名称终止进程。
- 安装和升级保留压缩包内的原文件名，不再把 OpenList 改名。
- 升级时在 `.old/` 备份实际使用的文件；支持从旧的 `alist.exe` 迁移到 `openlist.exe`。
- 解压函数同步关闭文件句柄，避免 Windows 在立即删除安装 ZIP 时报告文件占用。

现有配置格式和 rclone 启动参数不变。更新源沿用此上游提交的 OpenList 官方仓库。

## 验证

工具版本：Flutter 3.41.4 / Dart 3.11.1。

- 14 项文件名识别、优先级、备份名称、版本解析测试通过。
- 1 项 ZIP 解压及句柄释放测试通过。
- 2 项真实 OpenList v4.2.0 进程测试通过：首次安装及原名升级、旧文件名迁移。
- 真实进程测试在临时数据目录和独立本机端口中运行，验证服务 HTTP 响应、版本读取以及停止后释放端口。
- 修改涉及的 Dart 文件静态分析无问题。

运行检查：

```powershell
flutter pub get
dart run slang
dart run build_runner build --delete-conflicting-outputs
flutter test
# 可选：使用自己已有的 OpenList 二进制执行隔离进程测试。
$env:OPENLIST_TEST_BINARY = 'D:\OpenList\openlist.exe'
flutter test test/openlist_process_test.dart --reporter expanded
```

## Windows 便携包构建说明

常规完整构建需要 Flutter 和 Visual Studio 的桌面 C++ 构建工具：

```powershell
flutter build windows --release
```

本次便携包重新编译了修改后的 Dart AOT 程序与资源。未修改的启动器及原生插件来自同一上游提交的官方 Beta 包：

https://github.com/Xmarmalade/alisthelper/releases/download/beta/Release-windows-x64-20260313-6d7e1acb86a5c67bcf86d99bc6034f130b1d04c2.zip

官方 Beta 的 `flutter_windows.dll` 与本次 SDK 的 Release 运行库 SHA-256 完全一致：

`E225762642535E2F31B9EBB3D7DEF4DAE93162D357E09BEE241E19D461B9FF46`

Dart AOT 构建命令：

```powershell
flutter assemble '-dTargetPlatform=windows-x64' '-dBuildMode=release' '-dTargetFile=lib/main.dart' '-dTreeShakeIcons=true' '--output=build/portable-assets' release_bundle_windows-x64_assets
```

打包时以官方 Beta 的启动器、插件和运行库为基础，使用本次生成的 `windows/app.so` 和 `flutter_assets/` 替换 `data/` 中相应文件。

便携包尚未替换用户正在运行的安装，也未单独启动其 GUI。当前运行的 Helper 是单实例程序，运行本包前需先退出旧版 Helper。

## 使用方法

1. 退出正在运行的 Alist Helper，备份原 Helper 目录。
2. 将便携包完整解压到一个新目录，保留所有 DLL 与 `data/` 文件。
3. 服务停止后，可将此前改名的 OpenList 从 `alist.exe` 改回 `openlist.exe`。
4. 启动新目录中的 `alisthelper.exe`，将工作目录指向现有 OpenList 目录。
5. 保留现有的 OpenList 数据目录和 rclone 配置。本包不包含 OpenList/rclone 二进制或用户账号配置。

如旧 Helper 启用了开机自启，使用便携版长期替换后，在新版本设置中重新开启开机自启，使启动路径指向新位置。

## 上游状态

截至 2026-10-20，官方仓库的公开 PR 列表中未发现完成此文件名适配的提交。
作者已在 issue #86 说明升级模块迁移到了 OpenList，但仍使用自动改名兼容：

https://github.com/Xmarmalade/alisthelper/issues/86#issuecomment-3064672558

本次修改仅保存在本地，尚未向 GitHub 上传代码或提交 PR。
