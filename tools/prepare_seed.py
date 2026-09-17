"""准备金元宝种子素材：抽样真实猫片 + 生成清单。

源：F:\元宝爱拍照\金元宝照片\
目标：pet_camera/assets/seed/photos/ (yuanbao_001.jpg ...)
产出：pet_camera/assets/seed/seed_manifest.json

数据模型对齐 Spec §6（pets/albums/photos）。
"""
import os
import shutil
import json
import datetime

SRC = r"F:\元宝爱拍照\金元宝照片"
DST_PHOTOS = r"F:\元宝爱拍照\pet_camera\assets\seed\photos"
MANIFEST = r"F:\元宝爱拍照\pet_camera\assets\seed\seed_manifest.json"

os.makedirs(DST_PHOTOS, exist_ok=True)

files = sorted(
    n for n in os.listdir(SRC)
    if n.lower().endswith((".jpg", ".jpeg"))
)

TARGET = 24
if len(files) > TARGET:
    step = len(files) / TARGET
    selected = [files[min(len(files) - 1, int(i * step))] for i in range(TARGET)]
else:
    selected = files

photos = []
for i, src_name in enumerate(selected):
    dst_name = f"yuanbao_{i + 1:03d}.jpg"
    shutil.copy2(os.path.join(SRC, src_name), os.path.join(DST_PHOTOS, dst_name))
    d = datetime.date(2026, 2, 2) + datetime.timedelta(days=i * 7)
    captured = datetime.datetime(d.year, d.month, d.day, 9 + (i % 8), (i * 13) % 60)
    album = "a_portrait" if i % 5 == 0 else "a_daily"
    photos.append({
        "id": f"p{i + 1:03d}",
        "petId": "yuanbao",
        "albumId": album,
        "fileName": dst_name,
        "capturedAt": captured.strftime("%Y-%m-%dT%H:%M:%S"),
        "source": "seed",
    })

manifest = {
    "pets": [{
        "id": "yuanbao",
        "name": "金元宝",
        "species": "cat",
        "breed": "英国短毛猫",
        "birthday": "2021-05-20",
        "avatarFileName": "yuanbao_001.jpg",
        "bio": "一只爱拍照的英短，也是本项目首席模特与种子数据来源。",
    }],
    "albums": [
        {"id": "a_daily", "petId": "yuanbao", "title": "日常抓拍"},
        {"id": "a_portrait", "petId": "yuanbao", "title": "写真时刻"},
    ],
    "photos": photos,
}
with open(MANIFEST, "w", encoding="utf-8") as f:
    json.dump(manifest, f, ensure_ascii=False, indent=2)

print(f"copied {len(selected)} photos -> {DST_PHOTOS}")
print(f"manifest -> {MANIFEST}")
