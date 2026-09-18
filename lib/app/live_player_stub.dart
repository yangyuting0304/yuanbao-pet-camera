// 非原生端（Web / 兜底）：没有本地文件与视频解码能力，直接回落到静态图。
//
// Web 端 PhotoStorage.saveLive 恒返回 null，相册里不会出现 LIVE 角标，
// 所以这个回落分支实际上不会被走到——它的存在只是为了让共享代码能编译。
import 'package:flutter/widgets.dart';

Widget buildLivePlayer(String path, {required Widget fallback}) => fallback;
