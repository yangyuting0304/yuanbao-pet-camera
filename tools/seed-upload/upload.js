#!/usr/bin/env node
/* eslint-disable no-console */
/**
 * 元宝拍拍 —— 种子图上传脚本
 *
 * 用途：把 assets/seed/photos/ 下的种子图外置到腾讯云 COS，并按
 * 「前缀 + 文件名」布局（与本地结构一致），让 App 端按 SeedConfig 拼 URL 访问。
 *
 * 部署拓扑：
 *   本地  assets/seed/photos/<fileName>
 *   远端  <COS_BUCKET>/seed/photos/<fileName>
 *   App   <SEED_BASE_URL>/photos/<fileName>   （SEED_BASE_URL 指到 seed/ 前缀）
 *
 * 特性：
 *   - 增量上传：同名且 MD5 一致的文件自动跳过，避免重复 PUT。
 *   - 一致性校验：上传后读取远端 ETag 比对本地 MD5，失败即中止。
 *   - 路径安全：文件名必须匹配 字母/数字/_/-/. 白名单，防路径穿越。
 *
 * 用法：
 *   $env:COS_SECRET_ID="..."; $env:COS_SECRET_KEY="..."
 *   $env:COS_BUCKET="pet-camera-xxx"; $env:COS_REGION="ap-guangzhou"
 *   node tools/seed-upload/upload.js            # 全量上传（含增量跳过）
 *   node tools/seed-upload/upload.js --dry-run  # 只列出待上传，不真正上传
 *
 * 依赖（在 tools/seed-upload 目录下执行一次）：
 *   npm i cos-nodejs-sdk-v5
 */

const fs = require('fs');
const path = require('path');
const crypto = require('crypto');

const ROOT = path.resolve(__dirname, '..', '..');
const SRC_DIR = path.join(ROOT, 'assets', 'seed', 'photos');
const REMOTE_PREFIX = 'seed/photos'; // 桶内目录前缀，与部署站点 seed/ 前缀对应

const args = process.argv.slice(2);
const DRY_RUN = args.includes('--dry-run');

const {
  COS_SECRET_ID = '',
  COS_SECRET_KEY = '',
  COS_BUCKET = '',
  COS_REGION = '',
} = process.env;

function checkEnv() {
  const missing = ['COS_SECRET_ID', 'COS_SECRET_KEY', 'COS_BUCKET', 'COS_REGION']
    .filter((k) => !process.env[k]);
  if (missing.length) {
    console.error(`缺少环境变量：${missing.join(', ')}`);
    process.exit(1);
  }
}

/** 文件是否安全（白名单校验，防路径穿越） */
function isSafeName(name) {
  return /^[A-Za-z0-9][A-Za-z0-9_.-]*$/.test(name);
}

/** 计算文件 MD5（COS ETag 对单对象上传即为 MD5 十六进制小写） */
function md5(buf) {
  return crypto.createHash('md5').update(buf).digest('hex');
}

(async () => {
  checkEnv();
  const COS = require('cos-nodejs-sdk-v5');
  const cos = new COS({
    SecretId: COS_SECRET_ID,
    SecretKey: COS_SECRET_KEY,
  });

  if (!fs.existsSync(SRC_DIR)) {
    console.error(`源目录不存在：${SRC_DIR}`);
    process.exit(1);
  }

  const files = fs
    .readdirSync(SRC_DIR, { withFileTypes: true })
    .filter((d) => d.isFile())
    .filter((d) => /\.(jpg|jpeg|png|webp)$/i.test(d.name));

  let toUpload = [];
  let skipped = 0;

  for (const f of files) {
    if (!isSafeName(f.name)) {
      console.warn(`跳过不安全文件名：${f.name}`);
      continue;
    }
    const full = path.join(SRC_DIR, f.name);
    const localMd5 = md5(fs.readFileSync(full));
    const key = `${REMOTE_PREFIX}/${f.name}`;

    let remoteMd5 = null;
    try {
      // 增量判断：head_object 拿远端 ETag（不含引号）
      const head = await new Promise((resolve, reject) => {
        cos.headObject(
          { Bucket: COS_BUCKET, Region: COS_REGION, Key: key },
          (err, data) => (err ? reject(err) : resolve(data)),
        );
      });
      remoteMd5 = String(head.ETag || '').replace(/"/g, '').toLowerCase();
    } catch {
      /* 远端不存在，直接走上传 */
    }

    if (remoteMd5 === localMd5) {
      skipped += 1;
    } else {
      toUpload.push({ name: f.name, full, key, md5: localMd5, size: fs.statSync(full).size });
    }
  }

  console.log(`共 ${files.length} 张图 | 已同步跳过 ${skipped} | 待上传 ${toUpload.length}`);
  if (DRY_RUN) {
    for (const u of toUpload) console.log(`  [待上传] ${u.key}  (${(u.size / 1024).toFixed(0)} KB)`);
    console.log('（dry-run 模式，未真正上传）');
    return;
  }

  let ok = 0;
  let failed = 0;
  for (const u of toUpload) {
    const data = fs.readFileSync(u.full);
    try {
      await new Promise((resolve, reject) => {
        cos.putObject(
          {
            Bucket: COS_BUCKET,
            Region: COS_REGION,
            Key: u.key,
            Body: data,
            ContentType: u.name.endsWith('.png') ? 'image/png' : 'image/jpeg',
            ACL: 'public-read',
          },
          (err) => (err ? reject(err) : resolve()),
        );
      });
      // 一致性校验：读回 ETag 与本地 MD5 比对
      const head = await new Promise((resolve, reject) => {
        cos.headObject(
          { Bucket: COS_BUCKET, Region: COS_REGION, Key: u.key },
          (err, d) => (err ? reject(err) : resolve(d)),
        );
      });
      const etag = String(head.ETag || '').replace(/"/g, '').toLowerCase();
      if (etag !== u.md5) {
        throw new Error(`ETag 不一致（${etag} != ${u.md5}）`);
      }
      ok += 1;
      console.log(`  [OK] ${u.key}`);
    } catch (e) {
      failed += 1;
      console.error(`  [FAIL] ${u.key}  ${e.message}`);
    }
  }

  console.log(`完成：成功 ${ok}，失败 ${failed}，跳过 ${skipped}`);
  if (failed > 0) process.exit(1);
  console.log('\n站点访问前缀（与 App 端 SEED_BASE_URL 对应）：');
  console.log(`  https://${COS_BUCKET}.cos-website.${COS_REGION}.myqcloud.com/seed/`);
  console.log('  或默认域名：');
  console.log(`  https://${COS_BUCKET}.cos.${COS_REGION}.myqcloud.com/seed/`);
})().catch((e) => {
  console.error('上传失败：', e);
  process.exit(1);
});
