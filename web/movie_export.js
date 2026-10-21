/* Local video encoder. No network, model or server. Output MIME matches bytes. */
window.yuanbaoExportMovie = async function (r) {
  if (typeof r === "string") r = JSON.parse(r);
  if (!window.MediaRecorder || !HTMLCanvasElement.prototype.captureStream) {
    throw new Error('浏览器不支持视频导出，请使用新版Chrome/Edge或手机App');
  }
  const mime = ['video/mp4;codecs=avc1.42E01E,mp4a.40.2',
    'video/webm;codecs=vp9,opus', 'video/webm;codecs=vp8,opus', 'video/webm']
    .find(x => MediaRecorder.isTypeSupported(x));
  if (!mime) throw new Error('此浏览器没有可用的视频编码器');
  if (document.hidden) throw new Error('请保持页面在前台再导出');
  const urls = [], images = [], chunks = [];
  let video, audio, stream, recorder, music, raf, timer, rejectRender;
  const url = (b64, type) => {
    const raw = atob(b64), a = new Uint8Array(raw.length);
    for (let i = 0; i < raw.length; i++) a[i] = raw.charCodeAt(i);
    const u = URL.createObjectURL(new Blob([a], { type }));
    urls.push(u); return u;
  };
  const loadImage = src => new Promise((resolve, reject) => {
    const im = new Image(); im.onload = () => resolve(im);
    im.onerror = () => reject(new Error('照片解码失败')); im.src = src;
  });
  const visibility = () => {
    if (document.hidden && rejectRender) rejectRender(new Error('导出已中断：请保持标签页在前台后重试'));
  };
  try {
    const canvas = document.createElement('canvas');
    canvas.width = 540; canvas.height = 960;
    const ctx = canvas.getContext('2d', { alpha: false });
    if (!ctx) throw new Error('Canvas初始化失败');
    for (const s of r.slides) images.push(await loadImage(url(s, 'image/png')));
    const overlay = r.overlay ? await loadImage(url(r.overlay, 'image/png')) : null;
    if (r.video) {
      video = document.createElement('video');
      video.playsInline = true; video.muted = true; video.preload = 'auto';
      video.src = url(r.video, r.videoExtension === 'webm' ? 'video/webm' : 'video/mp4');
      await new Promise((resolve, reject) => {
        video.onloadedmetadata = resolve;
        video.onerror = () => reject(new Error('此浏览器无法读取所选视频'));
      });
      if (r.trimStartMs + r.durationMs > video.duration * 1000 + 100) {
        throw new Error('裁剪区间超出视频时长');
      }
      if (r.trimStartMs > 0) {
        await new Promise(resolve => {
          video.onseeked = resolve; video.currentTime = r.trimStartMs / 1000;
        });
      }
    }
    stream = canvas.captureStream(24);
    if (r.music || (video && !r.muteOriginal)) {
      const AudioContext = window.AudioContext || window.webkitAudioContext;
      if (!AudioContext) throw new Error('此浏览器不支持配乐编码');
      audio = new AudioContext(); await audio.resume();
      if (audio.state !== 'running') throw new Error('请先点击页面，再重试配乐导出');
      const out = audio.createMediaStreamDestination();
      if (r.music) {
        const data = Uint8Array.from(atob(r.music), c => c.charCodeAt(0));
        const buffer = await audio.decodeAudioData(data.buffer);
        music = audio.createBufferSource(); music.buffer = buffer; music.loop = true;
        const gain = audio.createGain(); gain.gain.value = 0.6;
        music.connect(gain).connect(out);
      }
      if (video && !r.muteOriginal) audio.createMediaElementSource(video).connect(out);
      for (const track of out.stream.getAudioTracks()) stream.addTrack(track);
    }
    const draw = elapsed => {
      ctx.fillStyle = '#1f1b17'; ctx.fillRect(0, 0, 540, 960);
      if (video) {
        const scale = Math.min(540 / video.videoWidth, 960 / video.videoHeight);
        const w = video.videoWidth * scale, h = video.videoHeight * scale;
        ctx.drawImage(video, (540 - w) / 2, (960 - h) / 2, w, h);
      } else {
        const i = Math.max(0, Math.min(images.length - 1, Math.floor(elapsed / (r.secondsPerSlide * 1000))));
        ctx.drawImage(images[i], 0, 0, 540, 960);
      }
      if (overlay) ctx.drawImage(overlay, 0, 0, 540, 960);
    };
    draw(0);
    recorder = new MediaRecorder(stream, { mimeType: mime, videoBitsPerSecond: 2000000 });
    const stopped = new Promise((resolve, reject) => {
      recorder.ondataavailable = e => { if (e.data.size) chunks.push(e.data); };
      recorder.onstop = resolve; recorder.onerror = () => reject(new Error('视频编码失败'));
    });
    // Attach a handler immediately: cancellation must never leave a rejected promise unhandled.
    stopped.catch(() => {});
    recorder.start(500);
    if (music) music.start();
    if (video) await video.play();
    document.addEventListener('visibilitychange', visibility);
    await new Promise((resolve, reject) => {
      rejectRender = reject;
      const start = performance.now();
      timer = setTimeout(() => reject(new Error('导出超时，请缩短片段')), r.durationMs + 30000);
      const tick = now => {
        const elapsed = now - start;
        try {
          draw(elapsed);
          if (elapsed >= r.durationMs) resolve();
          else raf = requestAnimationFrame(tick);
        } catch (e) { reject(e); }
      };
      raf = requestAnimationFrame(tick);
    });
    recorder.stop(); await stopped;
    let blob = new Blob(chunks, { type: mime.startsWith('video/mp4') ? 'video/mp4' : 'video/webm' });
    // MediaRecorder WebM omits duration; add it so video_player can seek/re-edit.
    if (blob.type === 'video/webm') blob = await yuanbaoWebmDuration(blob, r.durationMs);
    if (!blob.size) throw new Error('视频编码器返回空文件');
    const base64 = await new Promise((resolve, reject) => {
      const reader = new FileReader(); reader.onerror = reject;
      reader.onload = () => resolve(reader.result.split('base64,')[1]);
      reader.readAsDataURL(blob);
    });
    return { base64, mimeType: mime.startsWith('video/mp4') ? 'video/mp4' : 'video/webm' };
  } finally {
    rejectRender = null; clearTimeout(timer); cancelAnimationFrame(raf);
    document.removeEventListener('visibilitychange', visibility);
    if (recorder && recorder.state !== 'inactive') recorder.stop();
    if (video) { video.pause(); video.removeAttribute('src'); video.load(); }
    if (music) { try { music.stop(); } catch (_) {} }
    if (stream) stream.getTracks().forEach(t => t.stop());
    if (audio) await audio.close();
    urls.forEach(u => URL.revokeObjectURL(u));
  }
};

async function yuanbaoWebmDuration(blob, durationMs) {
  const data = new Uint8Array(await blob.arrayBuffer());
  const vint = pos => {
    let len = 1; while (len <= 8 && !(data[pos] & (1 << (8 - len)))) len++;
    if (len > 8 || pos + len > data.length) throw new Error('WebM头部无效');
    let value = BigInt(data[pos] & ((1 << (8-len))-1));
    for (let i=1;i<len;i++) value = (value << 8n) | BigInt(data[pos+i]);
    return {pos,len,value,unknown:value === (1n << BigInt(7*len))-1n};
  };
  const element = pos => {
    let len=1;while(len<=4 && !(data[pos] & (1 << (8-len))))len++;
    let id=0;for(let i=0;i<len;i++)id=(id*256)+data[pos+i];
    const size=vint(pos+len),start=size.pos+size.len;
    return {id,size,start,end:size.unknown?data.length:start+Number(size.value)};
  };
  let segment,info;
  for(let p=0;p<data.length;) {const e=element(p);if(e.id===0x18538067){segment=e;break;}if(e.end<=p)break;p=e.end;}
  if(!segment)throw new Error('WebM缺少媒体段');
  for(let p=segment.start;p<segment.end;) {const e=element(p);if(e.id===0x1549a966){info=e;break;}if(e.end<=p)break;p=e.end;}
  if(!info || info.size.unknown)throw new Error('WebM缺少时间信息');
  let scale=1000000;
  for(let p=info.start;p<info.end;) {
    const e=element(p);
    if(e.id===0x2ad7b1){scale=0;for(let j=e.start;j<e.end;j++)scale=scale*256+data[j];}
    if(e.id===0x4489) {
      const out=data.slice(),view=new DataView(out.buffer);
      if(e.end-e.start===8)view.setFloat64(e.start,durationMs*1000000/scale);
      else view.setFloat32(e.start,durationMs*1000000/scale);
      return new Blob([out],{type:'video/webm'});
    }
    if(e.end<=p)break;p=e.end;
  }
  const extra=new Uint8Array(11);extra.set([0x44,0x89,0x88]);
  new DataView(extra.buffer).setFloat64(3,durationMs*1000000/scale);
  const out=new Uint8Array(data.length+11);
  out.set(data.subarray(0,info.end));out.set(extra,info.end);out.set(data.subarray(info.end),info.end+11);
  const writeSize=(s,value)=>{
    let v=BigInt(value);if(v>=(1n<<BigInt(7*s.len))-1n)throw new Error('WebM时间信息过长');
    for(let i=s.len-1;i>=0;i--){out[s.pos+i]=Number(v&255n);v>>=8n;}
    out[s.pos]|=1<<(8-s.len);
  };
  writeSize(info.size,info.size.value+11n);
  if(!segment.size.unknown)writeSize(segment.size,segment.size.value+11n);
  return new Blob([out],{type:'video/webm'});
}
