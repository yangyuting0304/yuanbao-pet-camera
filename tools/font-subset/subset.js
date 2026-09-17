#!/usr/bin/env node
/* eslint-disable no-console */
/**
 * 元宝拍拍 —— 中文字体子集化
 *
 * 背景：思源黑体 Noto Sans SC 原为 16.95 MB 的可变字体，全量打进 Web 产物与
 * Android 包，会造成 Web 首屏必下载十几 MB、APK 虚胖。
 *
 * 策略：保留「源码中出现的所有字符」∪「GB2312 一级字库」∪「ASCII/常用标点」，
 * 其余字形全部剔除；可变字重按需要 pin 成静态字重（gvar/fvar 删除后体积再降 ~40%）。
 *
 * 产物约定（App 运行时用 FontLoader 注册，见 lib/data/app_font.dart）：
 *   assets/fonts/NotoSansSC-400.ttf  常规字重
 *   assets/fonts/NotoSansSC-700.ttf  粗体（ThemeData 里的 w600 也会命中它）
 *
 * 母版：tools/font-subset/source/NotoSansSC-variable.ttf（GB2312 全集可变字体，
 * 3.57 MB）。拆分字重后必须基于母版重新生成，不能拿已 pin 的字体二次加工。
 *
 * 依赖（在 tools/font-subset 目录下执行一次）：
 *   npm i subset-font iconv-lite
 *
 * 用法：
 *   node tools/font-subset/subset.js --dry-run        # 只统计字符集，不写文件
 *   node tools/font-subset/subset.js --gb=level1      # 只保留 GB2312 一级字库（3755 常用字）
 *   node tools/font-subset/subset.js --pin=400        # 把可变字重固定到 400（体积更小）
 *   node tools/font-subset/subset.js --out=assets/fonts/NotoSansSC-400.ttf  # 输出到指定路径
 *   node tools/font-subset/subset.js --src=tools/font-subset/source/NotoSansSC-variable.ttf
 *                                                     # 指定母版（默认 assets/fonts/NotoSansSC.ttf）
 *   node tools/font-subset/subset.js --inspect=a.ttf,b.ttf  # 打印体积/字重/是否可变字体
 *
 * 重新生成两个字重（推荐命令，字符集变更或升级字库后执行）：
 *   node tools/font-subset/subset.js --src=tools/font-subset/source/NotoSansSC-variable.ttf ^
 *     --gb=level1 --pin=400 --out=assets/fonts/NotoSansSC-400.ttf
 *   node tools/font-subset/subset.js --src=tools/font-subset/source/NotoSansSC-variable.ttf ^
 *     --gb=level1 --pin=700 --out=assets/fonts/NotoSansSC-700.ttf
 */

const fs = require('fs');
const path = require('path');
const iconv = require('iconv-lite');
const subsetFontMod = require('subset-font');

const subsetFont = subsetFontMod.default || subsetFontMod;

const ROOT = path.resolve(__dirname, '..', '..');
// 母版字体：默认取仓库内的 NotoSansSC.ttf；拆分字重后可指向备份里的可变版本。
const FONT_PATH = path.resolve(
  ROOT,
  process.argv.slice(2).find((a) => a.startsWith('--src='))?.slice(6) ||
    path.join('assets', 'fonts', 'NotoSansSC.ttf'),
);
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
// 字库分级：full=GB2312 全量，level1=常用 3755 字，none=只保留源码字符
const GB_LEVEL = arg('gb', 'full');
// 输出路径：不传则覆盖 assets/fonts/NotoSansSC.ttf（自动备份）
const OUT = arg('out', '');
// 只读取已有字体文件并打印字重/是否可变字体（逗号分隔多个路径）
const INSPECT = arg('inspect', '');
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

/**
 * GB2312 汉字与符号。
 * - full  ：0xB0-0xF7 全部汉字（6763 个），覆盖生僻姓名/地名。
 * - level1：0xB0-0xD7 一级字库（3755 个常用字），体积约为前者的一半，
 *           足够覆盖 UI 文案与绝大多数用户输入。
 */
function gb2312Chars(level) {
  const set = new Set();
  const hiEnd = level === 'level1' ? 0xd7 : 0xf7;
  for (let hi = 0xb0; hi <= hiEnd; hi += 1) {
    for (let lo = 0xa1; lo <= 0xfe; lo += 1) {
      const s = iconv.decode(Buffer.from([hi, lo]), 'gb2312');
      if (s.length === 1 && s !== '�') set.add(s);
    }
  }
  return set;
}

/**
 * 读取 sfnt 表目录，报告字重与是否仍是可变字体。
 * 用途：--pin=700 之后必须确认 OS/2.usWeightClass 真的变成 700，
 * 否则运行时按字重注册会退化成 400（粗体变成合成加粗）。
 */
function describeFont(buf, label) {
  try {
    const numTables = buf.readUInt16BE(4);
    let off = 12;
    let os2 = -1;
    let fvar = -1;
    for (let i = 0; i < numTables; i += 1) {
      const tag = buf.toString('latin1', off, off + 4);
      const tableOff = buf.readUInt32BE(off + 8);
      if (tag === 'OS/2') os2 = tableOff;
      if (tag === 'fvar') fvar = tableOff;
      off += 16;
    }
    const weight = os2 >= 0 ? buf.readUInt16BE(os2 + 4) : null;
    console.log(
      `${label}：${mb(buf.length)} | OS/2.usWeightClass=${weight ?? '未知'} | ${fvar >= 0 ? '可变字体' : '静态字体'}`,
    );
  } catch (e) {
    console.log(`${label}：元信息解析失败（${e.message}）`);
  }
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
  if (INSPECT) {
    for (const p of INSPECT.split(',')) {
      const file = path.resolve(ROOT, p.trim());
      describeFont(fs.readFileSync(file), path.relative(ROOT, file));
    }
    return;
  }

  const fontBuf = fs.readFileSync(FONT_PATH);
  const src = sourceChars();
  const gb = PRESET === 'gb2312' ? gb2312Chars(GB_LEVEL) : new Set();
  const charset = new Set([...src, ...commonExtras(), ...gb]);
  const text = [...charset].sort().join('');

  // 源码里落在字库之外的汉字：这些字一并被保留，列出来便于人工确认
  const outside = [...src].filter((c) => c.charCodeAt(0) > 0x7f && !gb.has(c));
  if (PRESET === 'gb2312') {
    console.log(`源码中 GB2312(${GB_LEVEL}) 之外的字符 ${outside.length} 个（已全部保留）：${outside.join('')}`);
  }

  console.log(`字体：${path.relative(ROOT, FONT_PATH)}  原体积 ${mb(fontBuf.length)}`);
  console.log(`源码字符 ${src.size} 个 | 预设 ${PRESET}/${GB_LEVEL} | 合计字符集 ${charset.size} 个`);
  fs.writeFileSync(CHARS_FILE, text, 'utf8');
  console.log(`字表已写入 ${path.relative(ROOT, CHARS_FILE)}`);

  if (DRY_RUN) {
    console.log('（dry-run 模式，未生成字体）');
    return;
  }

  const opts = { targetFormat: 'sfnt' };
  if (PIN) opts.variationAxes = { wght: Number(PIN) };

  const out = await subsetFont(fontBuf, text, opts);

  const target = OUT ? path.resolve(ROOT, OUT) : FONT_PATH;
  if (!OUT) {
    fs.mkdirSync(BACKUP_DIR, { recursive: true });
    const stamp = new Date().toISOString().replace(/[:.]/g, '-').slice(0, 19);
    const backup = path.join(BACKUP_DIR, `NotoSansSC-${stamp}.ttf`);
    fs.copyFileSync(FONT_PATH, backup);
    console.log(`原字体已备份：${path.relative(ROOT, backup)}`);
  }

  fs.mkdirSync(path.dirname(target), { recursive: true });
  fs.writeFileSync(target, out);

  const saved = 100 - (out.length / fontBuf.length) * 100;
  console.log(`子集化完成：${mb(fontBuf.length)} -> ${mb(out.length)}  (-${saved.toFixed(1)}%)`);
  console.log(`输出：${path.relative(ROOT, target)}`);
  describeFont(out, '产物');
})().catch((e) => {
  console.error('子集化失败：', e);
  process.exit(1);
});
