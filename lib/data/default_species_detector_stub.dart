// Web / 兜底实现：TFLite 在浏览器不可用，直接云端识别。
import 'cloud_species_detector.dart';
import 'pet_species_detector.dart';

PetSpeciesDetector create() => CloudSpeciesDetector();
