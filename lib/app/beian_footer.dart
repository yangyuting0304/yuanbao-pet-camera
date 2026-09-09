import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:pet_camera/app/tokens.dart';

/// 全站备案号 Footer（工信部合规要求）。
/// 通过 MaterialApp.builder 全局包裹，所有路由页面底部固定展示。
class BeianFooter extends StatelessWidget {
  const BeianFooter({super.key});

  /// 网站备案号（与备案系统一致）
  static const String beianNumber = '粤ICP备2026033457号';

  /// 工信部备案管理系统
  static const String beianUrl = 'https://beian.miit.gov.cn/';

  /// 公安机关备案号
  static const String gonganNumber = '粤公网安备44030002016568号';

  /// 全国互联网安全管理服务平台
  static const String gonganUrl =
      'https://www.beian.gov.cn/portal/registerSystemInfo?recordcode=44030002016568';

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final divider = Theme.of(context).dividerColor;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
      decoration: BoxDecoration(
        color: tokens.surface,
        border: Border(top: BorderSide(color: divider)),
      ),
      child: Center(
        child: Wrap(
          alignment: WrapAlignment.center,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 8,
          children: <Widget>[
            Text(
              '© 2026 杨玉婷作品集',
              style: TextStyle(
                fontSize: AppUi.fontCaption,
                color: tokens.textSecondary,
              ),
            ),
            InkWell(
              onTap: () => launchUrl(Uri.parse(beianUrl)),
              child: Text(
                beianNumber,
                style: TextStyle(
                  fontSize: AppUi.fontCaption,
                  color: tokens.brand,
                  decoration: TextDecoration.underline,
                ),
              ),
            ),
            Text(
              '|',
              style: TextStyle(
                fontSize: AppUi.fontCaption,
                color: tokens.textSecondary,
              ),
            ),
            InkWell(
              onTap: () => launchUrl(Uri.parse(gonganUrl)),
              child: Text(
                gonganNumber,
                style: TextStyle(
                  fontSize: AppUi.fontCaption,
                  color: tokens.brand,
                  decoration: TextDecoration.underline,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
