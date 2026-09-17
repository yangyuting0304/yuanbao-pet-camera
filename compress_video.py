import subprocess, os, json, sys

SRC = r"F:\元宝爱拍照\pet_camera\assets\seed\photos\feat_video.mp4"
DST = r"F:\元宝爱拍照\pet_camera\assets\seed\photos\feat_video_compressed.mp4"
THUMB = r"F:\元宝爱拍照\pet_camera\assets\seed\photos\feat_video_thumb.jpg"

import imageio_ffmpeg
ff = imageio_ffmpeg.get_ffmpeg_exe()
print("ffmpeg:", ff)

# 1) probe
probe = subprocess.run([ff, "-i", SRC], stderr=subprocess.PIPE, text=True)
stderr = probe.stderr
print("===== PROBE =====")
print(stderr)

# 解析时长/分辨率
import re
dur_m = re.search(r"Duration:\s*(\d+):(\d+):(\d+\.\d+)", stderr)
w_m = re.search(r"(\d{3,4})x(\d{3,4})", stderr)
dur = None
if dur_m:
    h, m, s = map(float, dur_m.groups())
    dur = h*3600 + m*60 + s
print("duration:", dur)
if w_m:
    print("resolution:", w_m.group(0))

# 2) 压缩：竖屏 480x854(9:16), 静音, 码率600k, 快速start, 裁剪到前12秒
#    卡片很小，480宽足够清晰；H.264 + faststart 利于流式自动播放
scale_vf = "scale=480:854:force_original_aspect_ratio=decrease,pad=480:854:(ow-iw)/2:(oh-ih)/2,setsar=1"
cmd = [
    ff, "-y", "-i", SRC,
    "-t", "12",                       # 最长取前12秒做循环
    "-vf", scale_vf,
    "-c:v", "libx264", "-profile:v", "high", "-level", "3.1",
    "-b:v", "600k", "-maxrate", "800k", "-bufsize", "1200k",
    "-r", "25",
    "-an",                            # 不要音频（卡片静音）
    "-pix_fmt", "yuv420p",
    "-movflags", "+faststart",
    "-preset", "veryfast",
    DST,
]
print("===== COMPRESS =====")
print(" ".join(cmd))
r = subprocess.run(cmd, stderr=subprocess.STDOUT, stdout=subprocess.PIPE, text=True)
print(r.stdout[-1500:])

sz_src = os.path.getsize(SRC)
sz_dst = os.path.getsize(DST) if os.path.exists(DST) else 0
print(f"===== RESULT =====\nSRC: {sz_src/1024/1024:.2f} MB\nDST: {sz_dst/1024/1024:.2f} MB\nratio: {sz_dst/sz_src*100:.1f}%")

# 3) 重新抽首帧（视频被缩放/裁剪，首帧也更新以保证封面一致）
thumb_cmd = [ff, "-y", "-i", DST, "-ss", "0.1", "-frames:v", "1", "-q:v", "3", THUMB]
subprocess.run(thumb_cmd, stderr=subprocess.DEVNULL)
print("thumb regenerated:", os.path.exists(THUMB), os.path.getsize(THUMB) if os.path.exists(THUMB) else 0)
