import os, time, shutil, zipfile

WEB = r'F:\元宝爱拍照\pet_camera\build\web'
DEST = r'F:\元宝爱拍照\pet_camera\build\yuanbao-pet-camera'
ZIP = r'F:\元宝爱拍照\pet_camera\build\web-deploy.zip'

# 1) 修正 renderer: canvaskit -> html (手机免 3-4MB wasm 下载白屏)
bs = os.path.join(WEB, 'flutter_bootstrap.js')
with open(bs, 'r', encoding='utf-8') as f:
    s = f.read()
if '"renderer":"canvaskit"' in s:
    s = s.replace('"renderer":"canvaskit"', '"renderer":"html"')
    with open(bs, 'w', encoding='utf-8') as f:
        f.write(s)
    print('renderer -> html')
else:
    print('renderer already html or not found token')

# 2) 同步 build/web -> build/yuanbao-pet-camera (覆盖)
def copy_with_retry(src, dst, tries=8):
    for i in range(tries):
        try:
            shutil.copy2(src, dst)
            return True
        except PermissionError:
            time.sleep(1.0)
    # 最后尝试直接读写替换
    try:
        with open(src, 'rb') as f:
            data = f.read()
        with open(dst, 'wb') as f:
            f.write(data)
        return True
    except Exception as e:
        print('COPY FAIL', src, e)
        return False

count = 0
for root, dirs, files in os.walk(WEB):
    rel = os.path.relpath(root, WEB)
    target_dir = os.path.join(DEST, rel) if rel != '.' else DEST
    os.makedirs(target_dir, exist_ok=True)
    for fn in files:
        src = os.path.join(root, fn)
        dst = os.path.join(target_dir, fn)
        if fn == 'flutter_bootstrap.js':
            copy_with_retry(src, dst)
        else:
            shutil.copy2(src, dst)
        count += 1
print('synced files:', count)

# 3) 重新打包 web-deploy.zip（zip 根直接是 web 产物，用户解压进 ECS 的 yuanbao-pet-camera 目录）
if os.path.exists(ZIP):
    os.remove(ZIP)
with zipfile.ZipFile(ZIP, 'w', zipfile.ZIP_DEFLATED) as z:
    for root, dirs, files in os.walk(WEB):
        for fn in files:
            fp = os.path.join(root, fn)
            arc = os.path.relpath(fp, WEB)
            z.write(fp, arc)
print('zip written:', ZIP, os.path.getsize(ZIP), 'bytes')
