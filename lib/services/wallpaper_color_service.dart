import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

class WallpaperColorService {
  WallpaperColorService._();

  static const _maxWallpaperBytes = 40 * 1024 * 1024;

  static Future<Color?> detectSeedColor() async {
    if (!Platform.isWindows) return null;

    for (final file in await _wallpaperCandidates()) {
      try {
        if (!await file.exists()) continue;
        if (await file.length() > _maxWallpaperBytes) continue;
        final bytes = await file.readAsBytes();
        final color = await _extractSeedColor(bytes);
        if (color != null) return color;
      } catch (_) {}
    }

    return _solidBackgroundColor();
  }

  static Future<List<File>> _wallpaperCandidates() async {
    final files = <File>[];
    final wallpaperPath = await _registryValue(
      r'HKCU\Control Panel\Desktop',
      'WallPaper',
    );
    if (wallpaperPath != null && wallpaperPath.isNotEmpty) {
      files.add(File(wallpaperPath));
    }

    final appData = Platform.environment['APPDATA'];
    if (appData != null && appData.isNotEmpty) {
      files.add(
        File(
          p.join(
            appData,
            'Microsoft',
            'Windows',
            'Themes',
            'TranscodedWallpaper',
          ),
        ),
      );
    }
    return files;
  }

  static Future<Color?> _solidBackgroundColor() async {
    final raw = await _registryValue(
      r'HKCU\Control Panel\Colors',
      'Background',
    );
    if (raw == null || raw.isEmpty) return null;

    final parts = raw
        .split(RegExp(r'\s+'))
        .map(int.tryParse)
        .whereType<int>()
        .toList();
    if (parts.length < 3) return null;
    return Color.fromARGB(
      255,
      parts[0].clamp(0, 255),
      parts[1].clamp(0, 255),
      parts[2].clamp(0, 255),
    );
  }

  static Future<String?> _registryValue(String key, String name) async {
    try {
      final result = await Process.run(
        'reg',
        ['query', key, '/v', name],
      ).timeout(const Duration(seconds: 3));
      if (result.exitCode != 0) return null;

      final pattern = RegExp(
        '^\\s*${RegExp.escape(name)}[ \\t]+REG_\\w+[ \\t]+(.+?)\\s*\$',
        multiLine: true,
      );
      return pattern.firstMatch(result.stdout.toString())?.group(1)?.trim();
    } catch (_) {
      return null;
    }
  }

  static Future<Color?> _extractSeedColor(Uint8List bytes) async {
    ui.Codec? codec;
    ui.Image? image;
    try {
      codec = await ui.instantiateImageCodec(
        bytes,
        targetWidth: 96,
        targetHeight: 96,
      );
      final frame = await codec.getNextFrame();
      image = frame.image;
      final data = await image.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      );
      if (data == null) return null;

      final pixels = data.buffer.asUint8List(
        data.offsetInBytes,
        data.lengthInBytes,
      );
      return _dominantColor(pixels);
    } catch (_) {
      return null;
    } finally {
      image?.dispose();
      codec?.dispose();
    }
  }

  static Color? _dominantColor(Uint8List rgba) {
    final buckets = List<_HueBucket?>.filled(24, null);
    var count = 0;
    var sumR = 0;
    var sumG = 0;
    var sumB = 0;

    for (var i = 0; i + 3 < rgba.length; i += 4) {
      final alpha = rgba[i + 3];
      if (alpha < 128) continue;

      final r = rgba[i];
      final g = rgba[i + 1];
      final b = rgba[i + 2];
      count++;
      sumR += r;
      sumG += g;
      sumB += b;

      final hsv = HSVColor.fromColor(Color.fromARGB(255, r, g, b));
      if (hsv.saturation < 0.15 ||
          hsv.value < 0.12 ||
          hsv.value > 0.95) {
        continue;
      }

      final index = (hsv.hue / 15).floor().clamp(0, 23);
      final weight =
          0.35 + hsv.saturation * (1 - (hsv.value - 0.55).abs());
      (buckets[index] ??= _HueBucket()).add(
        hsv.hue,
        hsv.saturation,
        hsv.value,
        weight,
      );
    }

    _HueBucket? best;
    for (final bucket in buckets) {
      if (bucket == null) continue;
      if (best == null || bucket.weight > best.weight) best = bucket;
    }

    if (best == null) {
      if (count == 0) return null;
      return Color.fromARGB(
        255,
        sumR ~/ count,
        sumG ~/ count,
        sumB ~/ count,
      );
    }

    return HSVColor.fromAHSV(
      1,
      best.hue,
      best.saturation.clamp(0.45, 0.85).toDouble(),
      best.value.clamp(0.42, 0.72).toDouble(),
    ).toColor();
  }
}

class _HueBucket {
  double weight = 0;
  double _cos = 0;
  double _sin = 0;
  double _saturation = 0;
  double _value = 0;

  void add(double hue, double saturation, double value, double amount) {
    final radians = hue * math.pi / 180;
    _cos += math.cos(radians) * amount;
    _sin += math.sin(radians) * amount;
    _saturation += saturation * amount;
    _value += value * amount;
    weight += amount;
  }

  double get hue {
    var degrees = math.atan2(_sin, _cos) * 180 / math.pi;
    if (degrees < 0) degrees += 360;
    return degrees;
  }

  double get saturation => weight == 0 ? 0 : _saturation / weight;

  double get value => weight == 0 ? 0 : _value / weight;
}
