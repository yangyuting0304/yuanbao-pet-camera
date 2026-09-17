// 一次性迁移：把本地 assets/seed/seed_manifest.json 转成 seed.json 并上传到 COS。
//
// 目的：相册的宠物/相册/种子图数据从「打进安装包的静态资源」迁到「COS 远端清单」，
//      后续改数据无需重新构建前端。用户动态作品单独存在 works.json（见 index.js）。
//
// 用法（在 cloud_functions/ai_portrait 目录）：
//   node migrate-seed.js
//
// 依赖环境变量（读同目录 .env）：TENCENT_COS_SECRET_ID/KEY/BUCKET/REGION
// 产物：COS 根目录 seed.json，结构 { version, pets, albums, photos }
//   photos 每条增加 type='seed_photo' 与 url（用 SEED_BASE_URL 拼出完整远程地址）

require('dotenv').config();
const fs = require('fs');
const path = require('path');
const COS = require('cos-nodejs-sdk-v5');

const ROOT = path.resolve(__dirname, '..', '..');
const MANIFEST = path.join(ROOT, 'assets', 'seed', 'seed_manifest.json');
const SEED_BASE_URL =
  (process.env.SEED_BASE_URL || '').replace(/\/+$/, '') ||
  `https://${process.env.TENCENT_COS_BUCKET}.cos.${process.env.TENCENT_COS_REGION || 'ap-guangzhou'}.myqcloud.com/seed`;

function requireEnv(name) {
  const v = process.env[name];
  if (!v) {
    console.error(`缺少环境变量 ${name}，请检查 .env`);
    process.exit(1);
  }
  return v;
}

async function main() {
  const bucket = requireEnv('TENCENT_COS_BUCKET');
  const region = process.env.TENCENT_COS_REGION || 'ap-guangzhou';
  requireEnv('TENCENT_COS_SECRET_ID');
  requireEnv('TENCENT_COS_SECRET_KEY');

  if (!fs.existsSync(MANIFEST)) {
    console.error(`找不到清单文件：${MANIFEST}`);
    process.exit(1);
  }
  const src = JSON.parse(fs.readFileSync(MANIFEST, 'utf8'));

  // photos 补齐 type 与 url（沿用 SeedConfig 的「前缀 + 文件名」拼接规则）。
  const photos = (src.photos || []).map((p) => ({
    ...p,
    type: 'seed_photo',
    url: `${SEED_BASE_URL}/photos/${p.fileName}`,
  }));

  const doc = {
    version: 1,
    updatedAt: new Date().toISOString(),
    pets: src.pets || [],
    albums: src.albums || [],
    photos,
  };

  const cos = new COS({
    SecretId: process.env.TENCENT_COS_SECRET_ID,
    SecretKey: process.env.TENCENT_COS_SECRET_KEY,
  });

  await new Promise((resolve, reject) =>
    cos.putObject(
      {
        Bucket: bucket,
        Region: region,
        Key: 'seed.json',
        Body: Buffer.from(JSON.stringify(doc), 'utf8'),
        ContentType: 'application/json',
        ACL: 'public-read',
      },
      (err, data) => (err ? reject(err) : resolve(data)))
  );

  const url = `https://${bucket}.cos.${region}.myqcloud.com/seed.json`;
  console.log(`已上传 seed.json -> ${url}`);
  console.log(`  pets=${doc.pets.length} albums=${doc.albums.length} photos=${photos.length}`);
}

main().catch((e) => {
  console.error('迁移失败：', e && e.message ? e.message : e);
  process.exit(1);
});
