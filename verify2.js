const { chromium } = require('playwright');

(async () => {
  const browser = await chromium.launch({
    executablePath: 'C:\\Program Files\\Google\\Chrome\\Application\\chrome.exe',
    args: ['--no-sandbox', '--disable-dev-shm-usage', '--disable-gpu']
  });
  const page = await browser.newPage({ viewport: { width: 1200, height: 900 } });
  const errors = [];
  page.on('pageerror', e => errors.push('PAGEERROR: ' + e.message));
  page.on('console', m => { if (m.type() === 'error') errors.push('CONSOLE: ' + m.text()); });

  console.log('goto...');
  await page.goto('http://localhost:8101/yuanbao-pet-camera/', { waitUntil: 'domcontentloaded', timeout: 60000 });

  console.log('waiting for flt-glass-pane (max 60s)...');
  let engineReady = false;
  try {
    await page.waitForSelector('flt-glass-pane', { timeout: 60000 });
    engineReady = true;
    console.log('Engine root found!');
  } catch (e) {
    console.log('NO_ENGINE_ROOT:', e.message);
  }

  // 强制隐藏 loading，看后面有没有 App
  console.log('hiding loading overlay...');
  await page.evaluate(() => {
    const el = document.getElementById('app-loading');
    if (el) el.style.display = 'none';
  });

  // 再等几秒让 Flutter 完成渲染
  await new Promise(r => setTimeout(r, 5000));

  // 截图
  await page.screenshot({ path: 'F:/元宝爱拍照/pet_camera/build/verify2.png' });

  // 检查 flt-glass-pane 内部内容
  const info = await page.evaluate(() => {
    const glass = document.querySelector('flt-glass-pane');
    return {
      hasGlassPane: !!glass,
      glassInnerHtml: glass ? glass.innerHTML.slice(0, 300) : null,
      glassChildCount: glass ? glass.children.length : 0,
      bodyChildren: Array.from(document.body.children).map(c => c.tagName + (c.id ? '#' + c.id : '')).join(', ')
    };
  });
  console.log('ENGINE_INFO:', JSON.stringify(info, null, 2));

  const text = await page.evaluate(() => document.body.innerText).catch(() => '');
  console.log('BODY_TEXT:', JSON.stringify(text.slice(0, 400)));
  console.log('ERRORS:', errors.length ? errors.slice(0, 10).join(' || ') : 'none');
  console.log('ENGINE_READY:', engineReady);

  await browser.close();
})().catch(e => { console.error('SCRIPT_FAIL:', e); process.exit(1); });
