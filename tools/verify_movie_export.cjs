// Optional browser integration check: NODE_PATH must provide Playwright.
const { chromium } = require('playwright');
const fs = require('node:fs');
const path = require('node:path');
(async () => {
  const browser = await chromium.launch({ channel: 'chrome', headless: true });
  try {
    const page = await browser.newPage();
    if (process.env.YUANBAO_TEST_WEBM === '1') await page.evaluate(() => {
      const supports = MediaRecorder.isTypeSupported.bind(MediaRecorder);
      MediaRecorder.isTypeSupported = type => !type.startsWith('video/mp4') && supports(type);
    });
    await page.addScriptTag({ path: path.resolve('web/movie_export.js') });
    const result = await page.evaluate(async () => {
      const slide = color => {
        const c = document.createElement('canvas'); c.width = 540; c.height = 960;
        const ctx = c.getContext('2d'); ctx.fillStyle = color; ctx.fillRect(0,0,540,960);
        ctx.fillStyle = 'white'; ctx.font = '40px sans-serif'; ctx.fillText('Yuanbao test', 40, 150);
        return c.toDataURL('image/png').split(',')[1];
      };
      const bytes = new ArrayBuffer(44 + 16000 * 2); const d = new DataView(bytes);
      const str = (o,s) => [...s].forEach((c,i) => d.setUint8(o+i,c.charCodeAt(0)));
      str(0,'RIFF'); d.setUint32(4,bytes.byteLength-8,true); str(8,'WAVE');str(12,'fmt ');
      d.setUint32(16,16,true);d.setUint16(20,1,true);d.setUint16(22,1,true);d.setUint32(24,16000,true);
      d.setUint32(28,32000,true);d.setUint16(32,2,true);d.setUint16(34,16,true);str(36,'data');d.setUint32(40,32000,true);
      for(let i=0;i<16000;i++) d.setInt16(44+i*2, Math.sin(i/16000*Math.PI*2*440)*3000,true);
      const music = btoa(String.fromCharCode(...new Uint8Array(bytes)));
      const movie = await window.yuanbaoExportMovie({slides:[slide('#a82828'),slide('#2840a8')],
        secondsPerSlide:2, durationMs:4000, trimStartMs:0, muteOriginal:true, music});
      const raw = Uint8Array.from(atob(movie.base64), c => c.charCodeAt(0));
      const v = document.createElement('video'); v.muted = true;
      const u = URL.createObjectURL(new Blob([raw],{type:movie.mimeType})); v.src = u;
      await new Promise((resolve,reject) => {v.onloadedmetadata=resolve;v.onerror=reject;});
      if(v.videoWidth!==540 || v.videoHeight!==960 || raw.length<1000) throw new Error('Invalid exported file');
      const seconds = Number.isFinite(v.duration) ? v.duration : null;
      if (seconds === null || Math.abs(seconds - 4) > .5) throw new Error('Export duration metadata is missing or invalid');
      const sample = document.createElement('canvas');sample.width=540;sample.height=960;
      const pixelAt = async time => {
        await new Promise(resolve => {v.onseeked=resolve;v.currentTime=time;});
        sample.getContext('2d').drawImage(v,0,0,540,960);
        return [...sample.getContext('2d').getImageData(10,10,1,1).data];
      };
      const red = await pixelAt(.5), blue = await pixelAt(2.5);
      if(red[0] <= red[2] || blue[2] <= blue[0]) throw new Error('Slide ordering is incorrect in encoded file');
      URL.revokeObjectURL(u);
      // Test a real imported clip, trim, caption overlay, mute and re-encode.
      const overlay = document.createElement('canvas'); overlay.width=540;overlay.height=960;
      const x=overlay.getContext('2d');x.fillStyle='white';x.font='40px sans-serif';x.fillText('caption',80,850);
      const edited = await window.yuanbaoExportMovie({slides:[],video:movie.base64,
        videoExtension:movie.mimeType.includes('mp4')?'mp4':'webm',trimStartMs:0,durationMs:1500,muteOriginal:true,
        overlay:overlay.toDataURL('image/png').split(',')[1]});
      const slow = await window.yuanbaoExportMovie({slides:[],video:movie.base64,
        videoExtension:movie.mimeType.includes('mp4')?'mp4':'webm',trimStartMs:0,durationMs:3000,
        segments:[{start_ms:0,end_ms:1000,speed:1},{start_ms:1000,end_ms:1500,speed:.5},{start_ms:2500,end_ms:3500,speed:1}],
        subjectFill:true,focusX:.85,focusY:.5,zoom:1.2,muteOriginal:true});
      const slowUrl=URL.createObjectURL(new Blob([Uint8Array.from(atob(slow.base64),c=>c.charCodeAt(0))],{type:slow.mimeType}));
      v.src=slowUrl;await new Promise((resolve,reject)=>{v.onloadedmetadata=resolve;v.onerror=reject;});
      if(!Number.isFinite(v.duration)||Math.abs(v.duration-3)>.7)throw new Error('Speed-ramp duration is incorrect: '+v.duration);
      const before=await pixelAt(.5), after=await pixelAt(2.5);
      if(before[0]<=before[2]||after[2]<=after[0])throw new Error('Source cuts are incorrect');
      const motion=JSON.parse(await window.yuanbaoAnalyzeMovie({video:movie.base64,
        videoExtension:movie.mimeType.includes('mp4')?'mp4':'webm',startMs:0,durationMs:3500,focusX:.5,focusY:.5}));
      if(motion.length!==40||!motion.some(m=>m.motion>1.5))throw new Error('Motion analysis did not sample actual frames: '+JSON.stringify(motion));
      URL.revokeObjectURL(slowUrl);
      return {movie, edited, slow, slowSeconds:v.duration, motionSamples:motion.length,width:v.videoWidth,height:v.videoHeight, seconds};
    });
    const ext = result.movie.mimeType.includes('mp4') ? 'mp4' : 'webm';
    fs.mkdirSync('.dart_tool/movie_verification', {recursive:true});
    fs.writeFileSync(`.dart_tool/movie_verification/slideshow.${ext}`,Buffer.from(result.movie.base64,'base64'));
    fs.writeFileSync(`.dart_tool/movie_verification/trimmed.${ext}`,Buffer.from(result.edited.base64,'base64'));
    fs.writeFileSync(`.dart_tool/movie_verification/slow_moment.${ext}`,Buffer.from(result.slow.base64,'base64'));
    console.log(JSON.stringify({width:result.width,height:result.height,durationSeconds:result.seconds,
      mimeType:result.movie.mimeType, slideshowBytes:Buffer.from(result.movie.base64,'base64').length,
      trimmedBytes:Buffer.from(result.edited.base64,'base64').length,slowSeconds:result.slowSeconds,motionSamples:result.motionSamples}));
  } finally { await browser.close(); }
})().catch(e=>{console.error(e);process.exitCode=1;});
