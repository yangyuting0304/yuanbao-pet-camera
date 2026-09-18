import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pet_camera/data/captured_photos.dart';

void main() {
  /// 每个用例一个容器，避免状态串味。
  (ProviderContainer, CapturedPhotosNotifier) make() {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    return (container, container.read(capturedPhotosProvider.notifier));
  }

  Uint8List bytes(int n) => Uint8List.fromList(List<int>.filled(n, 1));

  group('动态照片：短片与照片的关联', () {
    test('attachLive 把短片关联到对应的照片', () {
      final (_, notifier) = make();
      final photo = notifier.add(bytes(4));

      notifier.attachLive(photo, '/data/live_1.mp4');

      expect(notifier.state.single.hasLive, isTrue);
      expect(notifier.state.single.livePath, '/data/live_1.mp4');
    });

    test('录制期间又拍了新照片，仍关联到正确的那一张', () {
      // 真实会发生：录制耗时 2 秒，用户完全可能在这期间再按快门。
      // 所以关联必须按实例定位，不能依赖列表下标。
      final (_, notifier) = make();
      final first = notifier.add(bytes(4));
      notifier.add(bytes(4)); // 第二张（列表最新在前）

      notifier.attachLive(first, '/data/live_a.mp4');

      expect(notifier.state[0].hasLive, isFalse, reason: '第二张不该被误关联');
      expect(notifier.state[1].livePath, '/data/live_a.mp4');
    });

    test('同毫秒连拍的两张不会互相串味', () {
      // 时间戳只精确到毫秒，紧挨着的两次拍摄可能落在同一毫秒。
      // 早期实现用 takenAt 匹配，会把短片同时挂到两张上（单测抓到过）。
      final (_, notifier) = make();
      final a = notifier.add(bytes(4));
      notifier.add(bytes(4));

      notifier.attachLive(a, '/data/a.mp4');

      final attached = notifier.state.where((p) => p.hasLive).toList();
      expect(attached, hasLength(1), reason: '只该有一张带上短片');
      expect(attached.single.livePath, '/data/a.mp4');
    });

    test('照片已被删除时关联不抛异常（短片成孤儿由存储层清理）', () {
      final (_, notifier) = make();
      final photo = notifier.add(bytes(4));
      notifier.remove(notifier.state.single);

      expect(() => notifier.attachLive(photo, '/data/x.mp4'), returnsNormally);
      expect(notifier.state, isEmpty);
    });

    test('未关联短片的照片 hasLive 为 false（相册不显示 LIVE 角标）', () {
      final (_, notifier) = make();
      notifier.add(bytes(4));

      expect(notifier.state.single.hasLive, isFalse);
      expect(notifier.state.single.livePath, isNull);
    });
  });
}
