# -*- coding: utf-8 -*-
"""把用户新增的宠物照片重压后加入种子目录 + 更新 seed_manifest.json。
只处理 source 目录中 mtime >= 2026-07-31 的图片，避免重复。"""
import os, re, json, datetime
from PIL import Image

ROOT = r'F:\元宝爱拍照'
SEED = os.path.join(ROOT, 'pet_camera', 'assets', 'seed', 'photos')
MANIFEST = os.path.join(ROOT, 'pet_camera', 'assets', 'seed', 'seed_manifest.json')
CUT = datetime.datetime(2026, 7, 31, 0, 0)
EXTS = ('.jpg', '.jpeg', '.png', '.webp', '.bmp')

# dir -> (pet前缀, id前缀, albumId, 起始序号)
MAP = {
    '金元宝照片':   ('yuanbao',     'yb', 'a_daily',     123),
    '小棉花照片':   ('xiaomianhua', 'mh', 'a_mh_daily',   18),
    '小汤圆照片':   ('xiaotangyuan','ty', 'a_ty_daily',   19),
}

man = json.load(open(MANIFEST, encoding='utf-8'))
existing_ids = {p['id'] for p in man['photos']}
existing_files = {p['fileName'] for p in man['photos']}

new_entries = []
summary = []
now = datetime.datetime(2026, 7, 31, 15, 16, 0)
idx = 0

for src_dir, (pet, idp, album, start) in MAP.items():
    sdir = os.path.join(ROOT, src_dir)
    if not os.path.isdir(sdir):
        continue
    imgs = []
    for f in os.listdir(sdir):
        p = os.path.join(sdir, f)
        if os.path.isfile(p) and f.lower().endswith(EXTS):
            if datetime.datetime.fromtimestamp(os.path.getmtime(p)) >= CUT:
                imgs.append(f)
    imgs.sort()
    n = start
    ok = 0
    saved = 0
    for f in imgs:
        src = os.path.join(sdir, f)
        out_name = f'{pet}_{n:03d}.jpg'
        out_path = os.path.join(SEED, out_name)
        if os.path.exists(out_path):
            print(f'  跳过已存在: {out_name}')
            continue
        try:
            im = Image.open(src)
            im.load()
        except Exception as e:
            print(f'  [跳过] 无法读取 {f}: {e}')
            continue
        try:
            im = im.convert('RGB')
            w, h = im.size
            scale = min(1.0, 1600.0 / max(w, h))
            if scale < 1.0:
                im = im.resize((max(1, int(w*scale)), max(1, int(h*scale))), Image.LANCZOS)
            im.save(out_path, 'JPEG', quality=82, optimize=True, progressive=True)
        except Exception as e:
            print(f'  [跳过] 保存失败 {f}: {e}')
            continue
        saved += os.path.getsize(out_path)
        # 生成唯一 id
        pid = f'{idp}{n:03d}'
        while pid in existing_ids:
            pid += 'x'
        existing_ids.add(pid)
        cap = (now + datetime.timedelta(seconds=idx)).strftime('%Y-%m-%dT%H:%M:%S')
        new_entries.append({
            'id': pid,
            'petId': pet,
            'albumId': album,
            'fileName': out_name,
            'capturedAt': cap,
            'source': 'seed',
        })
        idx += 1
        n += 1
        ok += 1
    summary.append((src_dir, pet, ok, saved))

man['photos'].extend(new_entries)
json.dump(man, open(MANIFEST, 'w', encoding='utf-8'), ensure_ascii=False, indent=2)
print('\n=== 处理结果 ===')
for d, pet, ok, saved in summary:
    print(f'  {d} ({pet}): 新增 {ok} 张, 重压后 {saved/1024/1024:.1f} MB')
print(f'  manifest 总 photo 数: {len(man["photos"])}')
print('  新增文件名:')
for e in new_entries:
    print('    ', e['fileName'])
