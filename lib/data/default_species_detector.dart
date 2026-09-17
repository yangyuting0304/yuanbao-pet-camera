/// 平台默认物种识别器工厂（条件导入门面）。
///
///   - Android / iOS：端侧 TFLite（MobileNetV2 量化）优先，
///     识别不出或异常自动退云端（[TieredSpeciesDetector] 级联）。
///   - Web：TFLite 不可用，直接云端（stub 兜底实现）。
///
/// 上层（pages.dart）只调 [createDefaultSpeciesDetector]，
/// 永远拿到一个 [PetSpeciesDetector]，不感知平台差异。
library;

import 'pet_species_detector.dart';

import 'default_species_detector_stub.dart'
    if (dart.library.io) 'default_species_detector_io.dart';

PetSpeciesDetector createDefaultSpeciesDetector() => create();
