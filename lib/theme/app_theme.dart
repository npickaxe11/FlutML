import 'package:flutter/material.dart';

ThemeData buildAppTheme({
  Brightness brightness = Brightness.light,
  Color? seedColor,
}) {
  final seed = seedColor ?? const Color(0xFF9E9E9E);
  final scheme = ColorScheme.fromSeed(seedColor: seed, brightness: brightness);

  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    // 使用自定义字体 so.otf
    fontFamily: 'CustomFont',
    // 稍微宽松的视觉密度，便于中文阅读
    visualDensity: VisualDensity.standard.copyWith(
      // 增加控件间距，使界面更不拥挤
      // 使用现有的 named 参数
      horizontal: 4,
      vertical: 4,
    ),

    // 自定义文本主题，确保字号适中
  );
}
