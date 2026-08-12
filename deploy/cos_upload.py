#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""元宝拍拍 - 上传 build/web 到腾讯云 COS 静态托管。

前置：
  pip install cos-python-sdk-v5
  # Windows PowerShell 设置环境变量后运行：
  $env:COS_SECRET_ID="xxx"; $env:COS_SECRET_KEY="xxx"
  $env:COS_BUCKET="pet-camera-xxxx"; $env:COS_REGION="ap-guangzhou"
  python deploy/cos_upload.py

输出：
  - 站点 HTTPS 地址（cos-website 域名，无需备案，iPhone Safari 可直接开相机）
  - 启用 AI 美颜所需的 dart-define 提示

注意：上传前请确认已在 COS 控制台开启「静态网站」，首页=index.html、错误页=index.html、强制 HTTPS。
"""
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


def content_type(name):
    return EXT_CT.get(os.path.splitext(name)[1].lower(), 'application/octet-stream')


def main():
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

    count = 0
    total = 0
    for dp, _, fns in os.walk(root):
        for fn in fns:
            full = os.path.join(dp, fn)
            key = os.path.relpath(full, root).replace(os.sep, '/')
            with open(full, 'rb') as f:
                data = f.read()
            client.put_object(
                Bucket=bucket,
                Body=data,
                Key=key,
                ContentType=content_type(fn),
                ACL='public-read',
            )
            count += 1
            total += len(data)

    web = f'https://{bucket}.cos-website.{region}.myqcloud.com/'
    print(f'上传完成：{count} 个文件，{total / 1024 / 1024:.1f} MB')
    print(f'站点地址（HTTPS，无需备案）：{web}')
    print('记得在 COS 控制台开启「静态网站」：首页=index.html、错误页=index.html、强制 HTTPS。')
    print('如需启用 AI 美颜，构建时加：'
          '--dart-define=AI_PROXY_URL=https://你的ECS或FC域名/api/beautify')


if __name__ == '__main__':
    main()
