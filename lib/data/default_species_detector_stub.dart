// Web / 兜底实现：**当前恒为「不识别」**（与原生端保持一致）。
//
// 产品已收敛为只拍猫，物种不再是需要判断的变量。Web 端原本走云端识别，
// 现在一并停用：省掉一次图片上传（隐私）与网络往返，行为也和原生端统一。
// 端侧与云端实现都还在（见 cloud_species_detector.dart / pet_species_detector.dart），
// 将来扩到狗/兔时把工厂改回去即可。
import 'pet_species_detector.dart';

PetSpeciesDetector create() => const NoSpeciesDetector();