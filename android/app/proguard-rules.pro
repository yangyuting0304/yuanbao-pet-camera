# 元宝拍拍 —— R8 混淆补充规则。
#
# tflite_flutter 传递依赖的 tensorflow-lite core 在编译期引用
# tensorflow-lite-api 模块的两个类（可选的反射工厂接口）。这两个模块与
# core 共用包名 org.tensorflow.lite，触发 AGP 唯一 namespace 校验，
# 因此本项目排除了 -gpu / -api 模块（只用 CPU 推理）。
# core 通过 ServiceLoader 查找该接口的实现，缺失时走内置工厂路径，
# 故按 AGP 生成的 missing_rules 用 -dontwarn 抑制即可（不混淆掉）。
-dontwarn org.tensorflow.lite.InterpreterFactoryApi
-dontwarn org.tensorflow.lite.annotations.UsedByReflection
