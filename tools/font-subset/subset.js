#!/usr/bin/env node
/* eslint-disable no-console */
/**
 * 元宝拍拍 —— 中文字体子集化
 *
 * 背景：assets/fonts/NotoSansSC.ttf 原为 16.95 MB 的可变字体，全量打进 Web 产物
 * 与 Android 包，造成 Web 首屏必下载 ~17 MB、APK 虚胖 ~17 MB。
 *
 * 策略：保留「源码中出现的所有字符」∪「GB2312 字库」∪「ASCII/常用标点」，
 * 其余字形全部剔除。输出文件名与 pubspec 声明一致，因此无需改动任何配置。
 *
 * 依赖（在 tools/font-subset 目录下执行一次）：
 *   npm i subset-font iconv-lite
 *
 * 用法：
 *   node tools/font-subset/subset.js --dry-run        # 只统计字符集，不写文件
 *   node tools/font-subset/subset.js                  # 生成并替换（自动备份原字体）
 *   node tools/font-subset/subset.js --preset=source  # 仅源码字符（最小，但用户输入会缺字）
 *   node tools/font-subset/subset.js --pin=400        # 把可变字重固定到 400（体积更小）
 */

const fs = require('fs');
const path = require('path');
const iconv = require('iconv-lite');
const subsetFontMod = require('subset-font');

const subsetFont = subsetFontMod.default || subsetFontMod;

const ROOT = path.resolve(__dirname, '..', '..');
const FONT_PATH = path.join(ROOT, 'assets', 'fonts', 'NotoSansSC.ttf');
const BACKUP_DIR = path.join(ROOT, 'build', 'font-backup');
const CHARS_FILE = path.join(__dirname, 'used_chars.txt');

const args = process.argv.slice(2);
const arg = (name, def) => {
  const hit = args.find((a) => a.startsWith(`--${name}=`));
  return hit ? hit.slice(name.length + 3) : def;
};
const has = (name) => args.includes(`--${name}`);

const DRY_RUN = has('dry-run');
const PRESET = arg('preset', 'gb2312');
const PIN = arg('pin', '');

const mb = (n) => `${(n / 1024 / 1024).toFixed(2)} MB`;

/** 递归收集需要扫描字符的源文件 */
function collectFiles() {
  const files = [];
  const walk = (dir, exts) => {
    if (!fs.existsSync(dir)) return;
    for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
      const p = path.join(dir, entry.name);
      if (entry.isDirectory()) {
        if (entry.name === 'font-subset') continue;
        walk(p, exts);
      } else if (exts.some((x) => entry.name.endsWith(x))) {
        files.push(p);
      }
    }
  };
  walk(path.join(ROOT, 'lib'), ['.dart']);
  const extra = [
    path.join(ROOT, 'assets', 'seed', 'seed_manifest.json'),
    path.join(ROOT, 'web', 'index.html'),
    path.join(ROOT, 'web', 'manifest.json'),
  ];
  for (const f of extra) if (fs.existsSync(f)) files.push(f);
  return files;
}

/** 源码中出现的所有非控制字符（排除 emoji 与私有区） */
function sourceChars() {
  const set = new Set();
  for (const f of collectFiles()) {
    const text = fs.readFileSync(f, 'utf8');
    for (const ch of text) {
      const cp = ch.codePointAt(0);
      if (cp >= 0x20 && cp < 0x1f000) set.add(ch);
    }
  }
  return set;
}

/** GB2312 全部汉字与符号（6763 汉字），覆盖用户自由输入的绝大多数场景 */
function gb2312Chars() {
  const set = new Set();
  for (let hi = 0xb0; hi <= 0xf7; hi += 1) {
    for (let lo = 0xa1; lo <= 0xfe; lo += 1) {
      const s = iconv.decode(Buffer.from([hi, lo]), 'gb2312');
      if (s.length === 1 && s !== '�') set.add(s);
    }
  }
  return set;
}

/** ASCII 可打印字符 + 常用中文标点（GB2312 已覆盖大部分，此处兜底） */
function commonExtras() {
  const set = new Set();
  for (let cp = 0x20; cp <= 0x7e; cp += 1) set.add(String.fromCharCode(cp));
  for (const ch of '　、。〈〉《》「」『』【】〔〕…—～·’“”‘’！？；：，．') {
    set.add(ch);
  }
  return set;
}

(async () => {
  const fontBuf = fs.readFileSync(FONT_PATH);
  const src = sourceChars();
  const gb = PRESET === 'gb2312' ? gb2312Chars() : new Set();
  const charset = new Set([...src, ...commonExtras(), ...gb]);
  const text = [...charset].sort().join('');

  // 源码里落在 GB2312 之外的汉字：这些字一并被保留，列出来便于人工确认
  const outside = [...src].filter((c) => c.charCodeAt(0) > 0x7f && !gb.has(c));
  if (PRESET === 'gb2312') {
    console.log(`源码中 GB2312 之外的字符 ${outside.length} 个（已全部保留）：${outside.join('')}`);
  }

  console.log(`字体：${path.relative(ROOT, FONT_PATH)}  原体积 ${mb(fontBuf.length)}`);
  console.log(`源码字符 ${src.size} 个 | 预设 ${PRESET} | 合计字符集 ${charset.size} 个`);
  fs.writeFileSync(CHARS_FILE, text, 'utf8');
  console.log(`字表已写入 ${path.relative(ROOT, CHARS_FILE)}`);

  if (DRY_RUN) {
    console.log('（dry-run 模式，未生成字体）');
    return;
  }

  const opts = { targetFormat: 'sfnt' };
  if (PIN) opts.variationAxes = { wght: Number(PIN) };

  const out = await subsetFont(fontBuf, text, opts);

  fs.mkdirSync(BACKUP_DIR, { recursive: true });
  const backup = path.join(BACKUP_DIR, 'NotoSansSC.ttf');
  fs.copyFileSync(FONT_PATH, backup);
  fs.writeFileSync(FONT_PATH, out);

  const saved = 100 - (out.length / fontBuf.length) * 100;
  console.log(`原字体已备份：${path.relative(ROOT, backup)}`);
  console.log(`子集化完成：${mb(fontBuf.length)} -> ${mb(out.length)}  (-${saved.toFixed(1)}%)`);
})().catch((e) => {
  console.error('子集化失败：', e);
  process.exit(1);
});
