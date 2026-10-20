# OpenList 适配版 v0.3.0

基于 [Xmarmalade/alisthelper](https://github.com/Xmarmalade/alisthelper) 提交 `6d7e1acb86a5c67bcf86d99bc6034f130b1d04c2`，保留 GPL-3.0 许可与原作者信息。

## 功能

- 工作目录直接接受 `openlist.exe`，同时兼容 `alist.exe`；两者同时存在时优先 OpenList。macOS/Linux 同样识别不带扩展名的文件。
- 启动、版本读取、管理员密码命令、停止及托盘退出使用实际检测到或启动的程序。
- 安装和升级保留 OpenList 原文件名；旧文件备份到工作目录下的 `.old/`。
- **设置 → 检查更新**可检查和更新 OpenList、rclone。Windows 自动筛选当前架构的标准 ZIP，避免误选 lite、Windows 7 和其他架构。
- rclone 更新时等待原进程退出，替换后恢复原先运行的命令和挂载。
- 兼容旧版直接执行 `rclone mount ...` 的配置，此模式不再误调用不存在的远程控制接口。
- ZIP 解压后立即释放文件句柄，修复 Windows 更新时文件被占用的问题。
- Helper 自身的更新入口指向本分支仓库。

## 安装和升级

在 [Releases](https://github.com/llf1370033659/alisthelper/releases/latest) 下载安装包或便携版。先退出旧 Helper 再安装；便携版必须完整解压，保留 DLL 和 `data/` 文件。

保留现有 OpenList 数据目录及 rclone 配置。服务停止后可以将此前改名的 OpenList 从 `alist.exe` 改回 `openlist.exe`。Helper 工作目录仍指向原 OpenList 目录；更换 Helper 安装位置后重新开启开机自启以更新路径。

发布包只包含 Helper，不包含 OpenList/rclone 本体、网盘凭据或用户数据。

## 构建与测试

已使用 Flutter 3.41.4 / Dart 3.11.1 验证。完整 Windows 构建需要 Visual Studio 桌面 C++ 构建工具。

```powershell
flutter pub get
dart run slang
dart run build_runner build --delete-conflicting-outputs
flutter test --reporter expanded
flutter build windows --release
```

可选的真实程序测试在独立临时目录和本机端口运行，不操作现用数据：

```powershell
$env:OPENLIST_TEST_BINARY = 'D:\OpenList\openlist.exe'
$env:RCLONE_TEST_ZIP = 'D:\Downloads\rclone-v1.75.2-windows-amd64.zip'
flutter test --reporter expanded
```

安装版本为官方最新稳定版时，可验证检查更新接口和安装包筛选：

```powershell
$env:HELPER_LIVE_CHECK_DIRECTORY = 'D:\OpenList'
flutter test test/update_checks_test.dart --reporter expanded
```

2026-10-20 使用 OpenList v4.2.7、rclone v1.75.2 验证了 21 项测试，包括安装、原名升级、旧文件名迁移、rclone 更新后恢复运行及官方最新版本查询。修改涉及的文件静态分析无问题。

本分支 `Windows release` 工作流在推送版本标签时完整编译 Windows 启动器、原生插件和 Dart 程序，生成安装程序、便携包、源码包及 SHA256 校验文件。上游原有发布工作流仅在上游仓库执行。

## 上游状态

截至 2026-10-20，官方仓库公开 PR 中未找到完成原文件名适配的提交。作者在 [issue #86](https://github.com/Xmarmalade/alisthelper/issues/86#issuecomment-3064672558) 说明升级模块已迁移到 OpenList，但仍通过自动改名兼容。本分支补齐原文件名调用链并修复 Windows 更新流程。
