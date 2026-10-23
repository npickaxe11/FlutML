import 'package:flutter_test/flutter_test.dart';
import 'package:minecraft_launcher/utils/offline_uuid.dart';

void main() {
  test('offline UUID is stable and version-3 shaped', () {
    final a = offlinePlayerUuid('Steve');
    final b = offlinePlayerUuid('Steve');
    expect(a, b);
    expect(a.length, 36);
    expect(a[14], '3');
  });
}
