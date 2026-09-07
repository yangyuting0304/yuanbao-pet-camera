#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""元宝拍拍 - 打包 Web 产物，便于上传到服务器（ECS）。

用法（仓库根目录执行，需先构建）：
  build_web.cmd                 # 构建（含 --base-href 与 --no-web-resources-cdn）
  python sync_build.py          # 产出副本目录 + zip

产出：
  1) build/yuanbao-pet-camera/  —— build/web 的副本，目录名与线上子路径一致，
     整目录上传到站点根目录后，通过 /yuanbao-pet-camera/ 访问。
  2) build/web-deploy.zip       —— 同样内容的 zip，zip 根直接是产物，
     用于宝塔等面板上传后解压。

说明：
  - 路径全部基于脚本所在目录（仓库根）推导，不写死盘符，换机器可直接跑。
  - 前端静态资源已不上传 COS；COS 现在只存照片 / 视频 / 相册清单
    （seed/、temp/、firered/ 前缀），由 tools/seed-upload 与各代理服务负责。
  - 上传方式见 ECS_DEPLOY.md（scp / FileZilla → /www/wwwroot/yangyuting.cloud + nginx）。
"""
import os
import shutil
import zipfile

REPO_DIR = os.path.dirname(os.path.abspath(__file__))
BUILD_DIR = os.path.join(REPO_DIR, 'build')
WEB = os.path.join(BUILD_DIR, 'web')
DEST = os.path.join(BUILD_DIR, 'yuanbao-pet-camera')
ZIP = os.path.join(BUILD_DIR, 'web-deploy.zip')


def main():
    if not os.path.isdir(WEB):
        print(f'未找到 {WEB}，请先执行 build_web.cmd（flutter build web --release）')
        return 1

    # 1) 同步 build/web -> build/yuanbao-pet-camera（覆盖同名文件）
    shutil.copytree(WEB, DEST, dirs_exist_ok=True)
    count = sum(len(files) for _, _, files in os.walk(DEST))
    print('synced files:', count)

    # 2) 重新打包 web-deploy.zip（zip 根直接是 web 产物）
    if os.path.exists(ZIP):
        os.remove(ZIP)
    with zipfile.ZipFile(ZIP, 'w', zipfile.ZIP_DEFLATED) as z:
        for root, _, files in os.walk(WEB):
            for fn in files:
                fp = os.path.join(root, fn)
                z.write(fp, os.path.relpath(fp, WEB))
    print('zip written:', ZIP, os.path.getsize(ZIP), 'bytes')
    print(f'上传方式：scp -r {DEST} root@<ECS_IP>:/www/wwwroot/yangyuting.cloud/')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
