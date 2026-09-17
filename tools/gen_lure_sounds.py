"""生成宠物引诱音效（占位素材）。

这些音效用纯 Python 标准库合成，目的是让「音效引诱」功能立刻可跑通、
可演示、可联调。**它们不是真实录音**——真正能吸引猫狗的声音必须用实拍录音，
拿到素材后直接覆盖 assets/sounds/ 下的同名文件即可，App 无需改代码。

用法：
    python tools/gen_lure_sounds.py
"""

from __future__ import annotations

import math
import os
import random
import struct
import wave

SAMPLE_RATE = 22050
OUT_DIR = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "assets", "sounds")


def _write_wav(name: str, samples: list[float]) -> None:
    """把 [-1, 1] 的浮点样本写成 16bit 单声道 WAV。"""
    os.makedirs(OUT_DIR, exist_ok=True)
    path = os.path.join(OUT_DIR, name)
    peak = max((abs(s) for s in samples), default=1.0) or 1.0
    scale = 0.88 / peak  # 留一点余量防削波
    frames = bytearray()
    for s in samples:
        v = int(max(-1.0, min(1.0, s * scale)) * 32767)
        frames += struct.pack("<h", v)
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SAMPLE_RATE)
        w.writeframes(bytes(frames))
    print(f"  {name:26s} {len(samples) / SAMPLE_RATE:4.2f}s  {len(frames) // 1024:4d} KB")


def _n(count: int) -> int:
    return int(SAMPLE_RATE * count)


def _adsr(i: int, total: int, attack: float, release: float) -> float:
    """简单包络：线性起音 + 指数收尾。"""
    a = max(1, int(total * attack))
    if i < a:
        return i / a
    tail = total - i
    r = max(1, int(total * release))
    if tail < r:
        return (tail / r) ** 1.6
    return 1.0


# ───────────────────────── 音色基元 ─────────────────────────


def tone_sweep(
    dur: float,
    f0: float,
    f1: float,
    harmonics: tuple[float, ...] = (1.0,),
    vibrato_hz: float = 0.0,
    vibrato_depth: float = 0.0,
    attack: float = 0.02,
    release: float = 0.3,
) -> list[float]:
    """频率从 f0 线性滑到 f1 的乐音（可带泛音与颤音）。"""
    total = _n(dur)
    out: list[float] = []
    phase = 0.0
    for i in range(total):
        t = i / total
        f = f0 + (f1 - f0) * t
        if vibrato_hz:
            f *= 1.0 + vibrato_depth * math.sin(2 * math.pi * vibrato_hz * i / SAMPLE_RATE)
        phase += 2 * math.pi * f / SAMPLE_RATE
        v = sum(a * math.sin(phase * k) for k, a in enumerate(harmonics, start=1))
        out.append(v * _adsr(i, total, attack, release) / len(harmonics))
    return out


def noise_crackle(
    dur: float,
    bursts_per_sec: float,
    hp: float = 0.55,
    brightness: float = 1.0,
    seed: int = 0,
) -> list[float]:
    """纸袋/塑料袋/草叶那类「窸窣声」：随机爆发包络 + 高通白噪。"""
    rng = random.Random(seed)
    total = _n(dur)
    # 爆发包络
    env = [0.0] * total
    n_bursts = max(1, int(dur * bursts_per_sec))
    for _ in range(n_bursts):
        start = rng.randrange(0, max(1, total - 1))
        length = rng.randint(_n(0.01), _n(0.06))
        amp = rng.uniform(0.4, 1.0)
        for k in range(length):
            idx = start + k
            if idx >= total:
                break
            env[idx] = max(env[idx], amp * math.exp(-4.0 * k / length))
    # 高通（一阶差分）+ 亮度调节
    prev = 0.0
    out: list[float] = []
    for i in range(total):
        w = rng.uniform(-1.0, 1.0) * brightness
        hpv = w - hp * prev
        prev = w
        out.append(hpv * env[i])
    return out


def click(dur: float, freq: float = 1600.0, decay: float = 9.0) -> list[float]:
    """短促敲击声。"""
    total = _n(dur)
    return [
        math.sin(2 * math.pi * freq * i / SAMPLE_RATE) * math.exp(-decay * i / total)
        for i in range(total)
    ]


def thud(dur: float, freq: float = 110.0) -> list[float]:
    """低频闷响（脚步/落地）。"""
    total = _n(dur)
    rng = random.Random(7)
    out: list[float] = []
    for i in range(total):
        env = math.exp(-11.0 * i / total)
        body = math.sin(2 * math.pi * freq * i / SAMPLE_RATE)
        grit = rng.uniform(-0.35, 0.35)
        out.append((body + grit) * env)
    return out


def sequence(*parts: list[float], gaps: tuple[float, ...] = ()) -> list[float]:
    """把若干片段用静音间隔拼接起来。"""
    out: list[float] = []
    for idx, part in enumerate(parts):
        out.extend(part)
        if idx < len(gaps):
            out.extend([0.0] * _n(gaps[idx]))
    return out


def fade(samples: list[float], ms: float = 12.0) -> list[float]:
    """首尾淡入淡出，避免爆音。"""
    k = _n(ms / 1000.0)
    k = min(k, len(samples) // 2)
    for i in range(k):
        g = i / k
        samples[i] *= g
        samples[-1 - i] *= g
    return samples


# ───────────────────────── 各物种音效 ─────────────────────────

SOUNDS: dict[str, str] = {}


def build() -> None:
    print(f"输出目录：{OUT_DIR}\n")

    # ── 猫 ──
    # 猫叫：基频 + 泛音 + 颤音的滑动音，模拟「喵」的听感。
    SOUNDS["cat_meow.wav"] = fade(
        tone_sweep(
            0.62, 520, 700, harmonics=(1.0, 0.5, 0.28, 0.12),
            vibrato_hz=22, vibrato_depth=0.05, attack=0.12, release=0.45,
        )
    )
    # 小鸟叫：几声短促高频滑音
    SOUNDS["cat_bird.wav"] = fade(
        sequence(
            *[
                tone_sweep(0.09, 3600, 5400, vibrato_hz=60, vibrato_depth=0.05)
                for _ in range(5)
            ],
            gaps=(0.06, 0.05, 0.07, 0.06),
        )
    )
    # 纸袋窸窣
    SOUNDS["cat_paperbag.wav"] = fade(noise_crackle(1.0, 26, hp=0.82, seed=11))

    # ── 狗 ──
    # 哨声：清晰的滑音，狗最敏感的一类
    SOUNDS["dog_whistle.wav"] = fade(
        tone_sweep(0.75, 1900, 3100, vibrato_hz=9, vibrato_depth=0.02,
                   attack=0.05, release=0.35)
    )
    # 吱吱球：两短声 + 颤音
    SOUNDS["dog_squeak.wav"] = fade(
        sequence(
            tone_sweep(0.2, 1250, 2500, harmonics=(1.0, 0.35), vibrato_hz=38,
                       vibrato_depth=0.12, attack=0.06, release=0.4),
            tone_sweep(0.17, 1350, 2400, harmonics=(1.0, 0.35), vibrato_hz=34,
                       vibrato_depth=0.12, attack=0.06, release=0.4),
            gaps=(0.12,),
        )
    )
    # 零食袋
    SOUNDS["dog_treatbag.wav"] = fade(noise_crackle(1.15, 22, hp=0.78, seed=23))
    # 门外脚步：三下低频闷响
    SOUNDS["dog_doorstep.wav"] = fade(
        sequence(thud(0.16), thud(0.15), thud(0.14), gaps=(0.24, 0.22))
    )

    # ── 兔 ──
    # 草叶摩擦：高频噪声 + 缓慢起伏
    SOUNDS["rabbit_leaf.wav"] = fade(noise_crackle(1.2, 15, hp=0.9, seed=37))
    # 翻塑料袋
    SOUNDS["rabbit_plasticbag.wav"] = fade(noise_crackle(1.15, 18, hp=0.72, seed=41))

    # ── 龙猫 ──
    # 坚果袋：更细密的窸窣
    SOUNDS["chinchilla_nutbag.wav"] = fade(noise_crackle(0.95, 34, hp=0.86, seed=53))
    # 轻敲：两三声清脆短音（龙猫对轻敲很敏感）
    SOUNDS["chinchilla_tap.wav"] = fade(
        sequence(
            click(0.09, 2100), click(0.08, 2500), click(0.07, 1900),
            gaps=(0.13, 0.12),
        )
    )

    for name, samples in SOUNDS.items():
        _write_wav(name, samples)

    print(f"\n共生成 {len(SOUNDS)} 个音效。")


if __name__ == "__main__":
    build()
