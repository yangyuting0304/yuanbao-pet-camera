// 元宝拍拍 —— 冒烟测试：确认 App 根组件可正常构建渲染。
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:pet_camera/app/app.dart';

void main() {
  testWidgets('App boots without exception', (WidgetTester tester) async {
    await tester.pumpWidget(const ProviderScope(child: PetCameraApp()));
    // 让首帧异步加载（种子图 / 主题）有机会跑完，再断言无异常。
    await tester.pump(const Duration(milliseconds: 500));
    expect(tester.takeException(), isNull);
  });
}
