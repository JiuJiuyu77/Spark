#!/usr/bin/env node
/**
 * make-appicon.mjs —— 生成 AppIcon（不依赖任何 npm 包）
 *
 * 为什么要自己画：安装工具（AltStore / TrollStore / 自签器）多数要求
 * .app 里有图标；缺图标时有的工具直接拒绝安装，这也是「明明有 ipa 却装不上」的常见原因。
 *
 * 做法：直接写 PNG 文件头 + zlib 压缩的像素数据（用 node 内置 zlib）。
 * 图形：圆角底 + 中间一道闪电（Workbench 取「火花/闪电」意）。
 *
 * 用法：node scripts/make-appicon.mjs Native/Resources/Assets.xcassets/AppIcon.appiconset
 */
import fs from 'node:fs';
import path from 'node:path';
import zlib from 'node:zlib';

/** 需要产出的尺寸（iOS 15+ 只需要 1024 主图 + 60@2x/3x） */
const SIZES = [
  { size: 120, name: 'AppIcon60x60@2x.png' },
  { size: 180, name: 'AppIcon60x60@3x.png' },
  { size: 1024, name: 'AppIcon-1024.png' },
];

const BG_TOP = [0x2f, 0x6f, 0xff];   // 蓝
const BG_BOTTOM = [0x00, 0xc2, 0xa8]; // 青
const BOLT = [0xff, 0xff, 0xff];

/** 闪电多边形（单位坐标 0..1），形状参考 SF Symbol "bolt.fill" */
const BOLT_POINTS = [
  [0.58, 0.10],
  [0.30, 0.54],
  [0.47, 0.54],
  [0.40, 0.90],
  [0.70, 0.44],
  [0.52, 0.44],
];

function insidePolygon(px, py, points) {
  let inside = false;
  for (let i = 0, j = points.length - 1; i < points.length; j = i++) {
    const [xi, yi] = points[i];
    const [xj, yj] = points[j];
    const intersect = yi > py !== yj > py && px < ((xj - xi) * (py - yi)) / (yj - yi) + xi;
    if (intersect) inside = !inside;
  }
  return inside;
}

/** 圆角矩形带超采样抗锯齿 */
function render(size) {
  const pixels = Buffer.alloc(size * size * 4);
  const SS = 3; // 3x3 超采样
  const radius = size * 0.22;

  for (let y = 0; y < size; y++) {
    for (let x = 0; x < size; x++) {
      let rSum = 0, gSum = 0, bSum = 0, aSum = 0;
      for (let sy = 0; sy < SS; sy++) {
        for (let sx = 0; sx < SS; sx++) {
          const px = x + (sx + 0.5) / SS;
          const py = y + (sy + 0.5) / SS;

          // 圆角形状判定
          const cx = Math.min(Math.max(px, radius), size - radius);
          const cy = Math.min(Math.max(py, radius), size - radius);
          const dx = px - cx;
          const dy = py - cy;
          const inRounded = dx * dx + dy * dy <= radius * radius;
          if (!inRounded) { aSum += 0; continue; }

          // 背景渐变
          const t = py / size;
          let r = BG_TOP[0] + (BG_BOTTOM[0] - BG_TOP[0]) * t;
          let g = BG_TOP[1] + (BG_BOTTOM[1] - BG_TOP[1]) * t;
          let b = BG_TOP[2] + (BG_BOTTOM[2] - BG_TOP[2]) * t;

          // 闪电
          const ux = px / size;
          const uy = py / size;
          if (insidePolygon(ux, uy, BOLT_POINTS)) {
            r = BOLT[0]; g = BOLT[1]; b = BOLT[2];
          }
          rSum += r; gSum += g; bSum += b; aSum += 1;
        }
      }
      const n = SS * SS;
      const i = (y * size + x) * 4;
      const cover = aSum / n;
      const denom = aSum || 1;
      pixels[i] = Math.round(rSum / denom);
      pixels[i + 1] = Math.round(gSum / denom);
      pixels[i + 2] = Math.round(bSum / denom);
      pixels[i + 3] = Math.round(cover * 255);
    }
  }
  return pixels;
}

/** 写 PNG：IHDR + IDAT(zlib) + IEND */
function png(size, pixels) {
  const raw = Buffer.alloc((size * 4 + 1) * size);
  for (let y = 0; y < size; y++) {
    raw[y * (size * 4 + 1)] = 0; // filter: none
    pixels.copy(raw, y * (size * 4 + 1) + 1, y * size * 4, (y + 1) * size * 4);
  }
  const idat = zlib.deflateSync(raw, { level: 9 });

  const chunk = (type, data) => {
    const len = Buffer.alloc(4);
    len.writeUInt32BE(data.length);
    const typeBuf = Buffer.from(type, 'ascii');
    const crcBuf = Buffer.alloc(4);
    crcBuf.writeUInt32BE(crc32(Buffer.concat([typeBuf, data])) >>> 0);
    return Buffer.concat([len, typeBuf, data, crcBuf]);
  };

  const ihdr = Buffer.alloc(13);
  ihdr.writeUInt32BE(size, 0);
  ihdr.writeUInt32BE(size, 4);
  ihdr[8] = 8;   // bit depth
  ihdr[9] = 6;   // color type: RGBA
  ihdr[10] = 0; ihdr[11] = 0; ihdr[12] = 0;

  return Buffer.concat([
    Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]),
    chunk('IHDR', ihdr),
    chunk('IDAT', idat),
    chunk('IEND', Buffer.alloc(0)),
  ]);
}

let crcTable = null;
function crc32(buf) {
  if (!crcTable) {
    crcTable = new Int32Array(256);
    for (let n = 0; n < 256; n++) {
      let c = n;
      for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1;
      crcTable[n] = c;
    }
  }
  let c = 0xffffffff;
  for (const b of buf) c = crcTable[(c ^ b) & 0xff] ^ (c >>> 8);
  return c ^ 0xffffffff;
}

const outDir = process.argv[2] || 'Native/Resources/Assets.xcassets/AppIcon.appiconset';
fs.mkdirSync(outDir, { recursive: true });

const contents = { images: [], info: { author: 'spark', version: 1 } };
for (const { size, name } of SIZES) {
  const file = path.join(outDir, name);
  fs.writeFileSync(file, png(size, render(size)));
  // @2x 表示 UI 上 60pt → 120px；@3x → 180px
  const scale = name.includes('@3x') ? '3x' : name.includes('@2x') ? '2x' : '1x';
  const points = size === 1024 ? '1024x1024'
    : `${size / (scale === '3x' ? 3 : 2)}x${size / (scale === '3x' ? 3 : 2)}`;
  contents.images.push({ filename: name, idiom: size === 1024 ? 'ios-marketing' : 'universal', scale, size: points });
  console.log(`生成 ${file}  ${size}x${size}  ${(fs.statSync(file).size / 1024).toFixed(1)} KB`);
}
fs.writeFileSync(path.join(outDir, 'Contents.json'), JSON.stringify(contents, null, 2) + '\n');
console.log('完成：', outDir);
