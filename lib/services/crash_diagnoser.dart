/// Scans game crash output for well-known failure signatures and produces
/// an actionable hint for the user.
class CrashDiagnoser {
  CrashDiagnoser._();

  /// Returns a short diagnosis for [logTail], or '' when nothing matches.
  static String diagnose(String logTail) {
    final t = logTail.toLowerCase();

    if (t.contains('gflw platform: <error>') ||
        t.contains('glfw platform: <error>') ||
        t.contains('no renderer available') ||
        t.contains('backend api: unknown')) {
      return '显卡/OpenGL 初始化失败：游戏无法创建渲染上下文。\n'
          '· 更新显卡驱动（笔记本双显卡尤其要更新 Intel 核显驱动）\n'
          '· Windows 设置 → 系统 → 屏幕 → 显示卡设置：把本启动器使用的 '
          'java.exe 添加进去并选择「高性能」（独立显卡）\n'
          '· 不要在远程桌面/远程控制会话中启动游戏\n'
          '· 若虚拟内存接近上限，请先关闭部分程序释放内存';
    }

    if (t.contains('outofmemoryerror') ||
        t.contains('unable to allocate') ||
        t.contains('native memory allocation')) {
      return '内存不足：JVM 无法分配足够内存。\n'
          '· 调低设置中的最大内存（如 2048M）后重试\n'
          '· 关闭其他占用内存的程序\n'
          '· 增大系统虚拟内存';
    }

    if (t.contains('unsupportedclassversionerror')) {
      return 'Java 版本不匹配：该 Minecraft 版本需要其他 Java 大版本。\n'
          '· 打开「版本」页点击该版本，按提示选择正确的 Java';
    }

    if (t.contains('unsatisfiedlinkerror') ||
        t.contains('cannot find dependent libraries')) {
      return '本地库缺失或损坏（natives）：\n'
          '· 到「版本」页删除该版本后重新下载\n'
          '· 杀毒软件可能拦截了 DLL 解压，请将游戏目录加入白名单';
    }

    if (t.contains('classnotfoundexception') ||
        t.contains('noclassdeffounderror')) {
      return '依赖库缺失（ClassNotFound）：\n'
          '· 版本文件可能不完整，建议删除该版本重新下载\n'
          '· Forge/Fabric 安装若中断过，请重新安装加载器';
    }

    if (t.contains('openal') && t.contains('error')) {
      return '音频设备初始化失败（通常不致命）：\n'
          '· 检查系统声音设备是否正常\n'
          '· 该问题一般不会阻止进入游戏';
    }

    if (t.contains('access is denied') ||
        t.contains('permission denied') ||
        t.contains('java.io.filenotfoundexception')) {
      return '文件访问被拒绝：\n'
          '· 以管理员身份运行启动器，或将游戏目录移出受保护的文件夹\n'
          '· 检查杀毒软件是否锁定了游戏目录';
    }

    if (t.contains('connection refused') ||
        t.contains('unknownhostexception') ||
        t.contains('timeout')) {
      return '网络请求失败：\n'
          '· 正版验证/皮肤站登录需要能访问对应服务器\n'
          '· 检查网络或代理设置后重试';
    }

    return '';
  }
}
