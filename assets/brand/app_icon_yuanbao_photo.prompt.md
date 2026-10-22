# 元宝拍拍 · 真实金元宝摄影师图标

2026-10-22，用户最终明确选用其贴回的蓝绿背景照片版。正式母版：`app_icon_yuanbao_photo.png`，1254×1254、RGB、不透明。未选用后续金渐层身体重绘版，也未选用此前扁平/卡通/元宝外形方案。

使用内置 imagegen，以用户提供的真实金元宝照片进行身份保留合成。最终认可的图片被用户重新贴回后，直接按原图归档，仅为各平台等比缩放，不再次重画脸或身体。完整原始宠物照片没有加入仓库。

## 生成提示词记录

Use case: identity-preserve / compositing. Edit the provided REAL PHOTO of the user's actual pet Jin Yuanbao into one square APP ICON. Preserve this specific cat's real facial identity, photographic fur, round broad cheeks, golden-brown shaded coat and darker forehead, white muzzle and chin, rose pink nose, the size/placement of both eyes. The eye on the RIGHT SIDE OF THE IMAGE has a distinct BROWN PIGMENT SECTOR/MARK INSIDE its otherwise green iris. Keep it clearly visible and localized; the LEFT eye remains cool seafoam-green. Both eyes open and fully visible, asymmetrical. Crop/recompose chest-up with the large recognizable head dominating. Add two small golden/ivory paws holding a SMALL ORIGINAL minimalist generic camera below the white chin, one paw on its shutter, attentively framing a photograph. Camera: warm cream matte rounded body, one dark teal circular lens, one shutter bump, no labels, branding, straps, complex dials or specific real-world model features. Artistic Instagram editorial photography, clean silhouette, muted petrol-blue/blue-green studio background contrasting golden fur, safe margins, full opaque square. Remove original watermark, bottom panel and all text. No ingot, bowl, coins, illustration or pre-rounded corners.

## 最终选择的保护点

- 画面右侧眼睛的棕色痕，位置不得镜像。
- 保留用户选定原图的脸、毛发与相机，不用被否决的身体优化版本替换。
- 简约相机无品牌标识、未指定具体相机型号；未作法律结论或权利保证。
- 平台资源由 `python tools/generate_app_icons.py` 生成；iOS不透明正方形，Web maskable额外安全留白。
