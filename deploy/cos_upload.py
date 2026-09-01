#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""元宝拍拍 - 上传 build/web 到腾讯云 COS 静态托管（增量版）。

前置：
  pip install cos-python-sdk-v5
  # Windows PowerShell 设置环境变量后运行：
  $env:COS_SECRET_ID="xxx"; $env:COS_SECRET_KEY="xxx"
  $env:COS_BUCKET="pet-camera-xxxx"; $env:COS_REGION="ap-guangzhou"
  python deploy/cos_upload.py              # 增量上传（同名且 ETag 一致跳过）
  python deploy/cos_upload.py --dry-run    # 只预览待上传/待删除，不真正执行
  python deploy/cos_upload.py --prune      # 增量 + 清理远端孤儿文件

说明：
  - 增量：单对象 PUT 的 ETag 即本地 MD5，head_object 比对后相同即跳过，
    避免每次全量重传（Flutter build 后未变化的文件占大头）。
  - 孤儿清理（--prune）：删除远端存在但本地 build/web 不存在的对象；
    自动保护 seed/、temp/、firered/ 前缀（种子图与代理临时图床，不属于本站资源）。
  - 上传前请确认已在 COS 控制台开启「静态网站」，首页=index.html、错误页=index.html、强制 HTTPS。
"""
import argparse
import hashlib
import os
import sys

EXT_CT = {
    '.html': 'text/html; charset=utf-8',
    '.js': 'application/javascript',
    '.mjs': 'application/javascript',
    '.css': 'text/css',
    '.json': 'application/json',
    '.map': 'application/json',
    '.png': 'image/png',
    '.jpg': 'image/jpeg',
    '.jpeg': 'image/jpeg',
    '.gif': 'image/gif',
    '.svg': 'image/svg+xml',
    '.ico': 'image/x-icon',
    '.wasm': 'application/wasm',
    '.woff': 'font/woff',
    '.woff2': 'font/woff2',
    '.ttf': 'font/ttf',
}

# 孤儿清理时保护的前缀（不属于本站静态资源）
PROTECTED_PREFIXES = ('seed/', 'temp/', 'firered/')


def content_type(name):
    return EXT_CT.get(os.path.splitext(name)[1].lower(), 'application/octet-stream')


def md5_hex(data):
    return hashlib.md5(data).hexdigest()


def main():
    parser = argparse.ArgumentParser(description='增量上传 build/web 到 COS')
    parser.add_argument('--dry-run', action='store_true', help='只预览，不真正上传/删除')
    parser.add_argument('--prune', action='store_true', help='上传后清理远端孤儿文件')
    args = parser.parse_args()

    sid = os.environ.get('COS_SECRET_ID')
    skey = os.environ.get('COS_SECRET_KEY')
    bucket = os.environ.get('COS_BUCKET')
    region = os.environ.get('COS_REGION')
    if not all([sid, skey, bucket, region]):
        print('缺少环境变量：需设置 COS_SECRET_ID, COS_SECRET_KEY, COS_BUCKET, COS_REGION')
        sys.exit(1)

    root = 'build/web'
    if not os.path.isdir(root):
        print(f'未找到 {root}，请先执行 flutter build web --release')
        sys.exit(1)

    try:
        from qcloud_cos import CosConfig, CosS3Client
    except ImportError:
        print('请先安装依赖：pip install cos-python-sdk-v5')
        sys.exit(1)

    config = CosConfig(Region=region, SecretId=sid, SecretKey=skey)
    client = CosS3Client(config)

    # 1) 收集本地文件（key -> 内容 MD5）
    local = {}
    for dp, _, fns in os.walk(root):
        for fn in fns:
            full = os.path.join(dp, fn)
            key = os.path.relpath(full, root).replace(os.sep, '/')
            with open(full, 'rb') as f:
                local[key] = md5_hex(f.read())

    # 2) 增量比对：head_object 拿远端 ETag（单对象 PUT 即 MD5 十六进制）
    to_upload = []
    for key, local_md5 in local.items():
        remote_etag = None
        try:
            head = client.head_object(Bucket=bucket, Key=key)
            remote_etag = str(head.get('ETag', '')).strip('"').lower()
        except Exception:
            remote_etag = None  # 远端不存在 → 直接上传
        if remote_etag != local_md5:
            to_upload.append(key)

    # 3) 孤儿收集（仅 --prune 时）
    to_delete = []
    if args.prune:
        try:
            remote_keys = set()
            marker = ''
            while True:
                resp = client.list_objects(Bucket=bucket, Marker=marker, MaxKeys=1000)
                contents = resp.get('Contents', [])
                remote_keys.update(c['Key'] for c in contents)
                if resp.get('IsTruncated') != 'true':
                    break
                marker = resp.get('NextMarker') or contents[-1]['Key']
            to_delete = sorted(
                k for k in remote_keys
                if k not in local and not k.startswith(PROTECTED_PREFIXES)
            )
        except Exception as e:
            print(f'孤儿扫描失败（跳过清理）：{e}')
            to_delete = []

    print(f'本地 {len(local)} 个文件 | 待上传 {len(to_upload)} | 待删除孤儿 {len(to_delete)}')
    if args.dry_run:
        for k in sorted(to_upload):
            print(f'  [待上传] {k}')
        for k in to_delete:
            print(f'  [待删除] {k}')
        print('（dry-run 模式，未真正执行）')
        return

    # 4) 上传
    ok = failed = 0
    total = 0
    for key in to_upload:
        full = os.path.join(root, key.replace('/', os.sep))
        with open(full, 'rb') as f:
            data = f.read()
        try:
            client.put_object(
                Bucket=bucket,
                Body=data,
                Key=key,
                ContentType=content_type(key),
                ACL='public-read',
            )
            ok += 1
            total += len(data)
        except Exception as e:
            failed += 1
            print(f'  [FAIL] {key}  {e}')

    # 5) 孤儿清理
    deleted = 0
    for key in to_delete:
        try:
            client.delete_object(Bucket=bucket, Key=key)
            deleted += 1
        except Exception as e:
            print(f'  [DEL-FAIL] {key}  {e}')

    web = f'https://{bucket}.cos-website.{region}.myqcloud.com/'
    print(f'上传完成：成功 {ok}，失败 {failed}（跳过 {len(local) - len(to_upload)}），删除孤儿 {deleted}')
    print(f'站点地址（HTTPS，无需备案）：{web}')
    print('记得在 COS 控制台开启「静态网站」：首页=index.html、错误页=index.html、强制 HTTPS。')
    print('如需启用 AI 美颜，构建时加：'
          '--dart-define=AI_PROXY_URL=https://你的ECS或FC域名/api/beautify')
    if failed > 0:
        sys.exit(1)


if __name__ == '__main__':
    main()
