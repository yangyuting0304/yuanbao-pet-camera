"""从 AI 生成的 1024x1024 主图导出各尺寸 App 图标。

用途:
  - web/favicon.png (32x32, 网页页签)
  - web/icons/Icon-{192,512}.png (PWA)
  - web/icons/Icon-maskable-{192,512}.png (PWA maskable, 内容缩至 78% 留安全区)
  - android/app/src/main/res/mipmap-*/ic_launcher.png (Android 启动图标)

用法:
  venv python tools/generate_app_icons.py
"""

from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
SRC = ROOT / "assets/brand/app_icon_master.png"

# maskable 图标安全区: 内容占画布比例, 四周用底色填充
MASKABLE_CONTENT_RATIO = 0.78

TARGETS = [
    ("web/favicon.png", 32),
    ("web/icons/Icon-192.png", 192),
    ("web/icons/Icon-512.png", 512),
    ("android/app/src/main/res/mipmap-mdpi/ic_launcher.png", 48),
    ("android/app/src/main/res/mipmap-hdpi/ic_launcher.png", 72),
    ("android/app/src/main/res/mipmap-xhdpi/ic_launcher.png", 96),
    ("android/app/src/main/res/mipmap-xxhdpi/ic_launcher.png", 144),
    ("android/app/src/main/res/mipmap-xxxhdpi/ic_launcher.png", 192),
]

MASKABLE_TARGETS = [
    ("web/icons/Icon-maskable-192.png", 192),
    ("web/icons/Icon-maskable-512.png", 512),
]


def main() -> None:
    img = Image.open(SRC).convert("RGB")
    # 主图统一为正方形
    side = min(img.size)
    left = (img.width - side) // 2
    top = (img.height - side) // 2
    img = img.crop((left, top, left + side, top + side))

    # 底色取四角中点均值, 用于 maskable 填充
    w, h = img.size
    corners = [
        img.getpixel((4, h // 2)),
        img.getpixel((w - 5, h // 2)),
        img.getpixel((w // 2, 4)),
    ]
    bg = tuple(sum(c[i] for c in corners) // len(corners) for i in range(3))

    for rel, size in TARGETS:
        out = ROOT / rel
        out.parent.mkdir(parents=True, exist_ok=True)
        img.resize((size, size), Image.LANCZOS).save(out, "PNG")
        print(f"ok  {rel}  {size}x{size}")

    for rel, size in MASKABLE_TARGETS:
        out = ROOT / rel
        out.parent.mkdir(parents=True, exist_ok=True)
        canvas = Image.new("RGB", (size, size), bg)
        inner = round(size * MASKABLE_CONTENT_RATIO)
        content = img.resize((inner, inner), Image.LANCZOS)
        offset = (size - inner) // 2
        canvas.paste(content, (offset, offset))
        canvas.save(out, "PNG")
        print(f"ok  {rel}  {size}x{size} (maskable)")

    print("done.")


if __name__ == "__main__":
    main()
