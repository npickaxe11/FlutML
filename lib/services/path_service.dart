import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class PathService {
  PathService._();
  static final PathService instance = PathService._();

  String? _customGameDir; // 自定义游戏目录基础路径（如 X.XX.X/ 格式）
  String? _gameDir;

  Future<String> defaultGameDirectory() async {
    // 如果设置了自定义基础路径，使用该路径加上版本ID
    if (_customGameDir != null && _customGameDir!.isNotEmpty) {
      // 默认游戏目录为自定义基础路径 + 版本ID
      // 但 defaultGameDirectory 没有版本ID参数，这里返回基础路径
      // 实际的版本路径由计算版本路径的方法使用
      return _customGameDir!;
    }
    if (Platform.isWindows) {
      final appData = Platform.environment['APPDATA'];
      if (appData != null && appData.isNotEmpty) {
        return p.join(appData, '.minecraft');
      }
    }
    final docs = await getApplicationSupportDirectory();
    return p.join(docs.path, '.minecraft');
  }

  /// 设置自定义游戏目录基础路径（如 X.XX.X/ 格式）
  /// 当设置了此值时，每个版本的文件夹将位于此基路径下的版本ID文件夹
  Future<void> setCustomGameDir(String? path) async {
    _customGameDir = path;
    if (path != null && path.isNotEmpty) {
      await Directory(path).create(recursive: true);
    }
  }

  Future<String> gameDirectory() async {
    if (_gameDir != null && _gameDir!.isNotEmpty) {
      return _gameDir!;
    }
    final dir = await defaultGameDirectory();
    await Directory(dir).create(recursive: true);
    _gameDir = dir;
    return dir;
  }

  Future<String> versionsDir() async =>
      p.join(await gameDirectory(), 'versions');

  Future<String> librariesDir() async =>
      p.join(await gameDirectory(), 'libraries');

  Future<String> assetsDir() async => p.join(await gameDirectory(), 'assets');

  Future<String> nativesDir(String versionId) async =>
      p.join(await versionsDir(), versionId, 'natives');

  Future<String> versionJsonPath(String versionId) async =>
      p.join(await versionsDir(), versionId, '$versionId.json');

  Future<String> versionJarPath(String versionId) async =>
      p.join(await versionsDir(), versionId, '$versionId.jar');

  Future<String> launcherOutputLogPath(String versionId) async =>
      p.join(await versionsDir(), versionId, 'launcher-output.log');

  Future<String> launcherConfigDir() async {
    final support = await getApplicationSupportDirectory();
    final dir = Directory(p.join(support.path, 'minecraft_launcher'));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir.path;
  }

  Future<String> modsDir(String versionId) async =>
      p.join(await versionsDir(), versionId, 'mods');

  Future<String> resourcePacksDir(String versionId) async =>
      p.join(await versionsDir(), versionId, 'resourcepacks');

  Future<String> shaderPacksDir(String versionId) async =>
      p.join(await versionsDir(), versionId, 'shaderpacks');
}
