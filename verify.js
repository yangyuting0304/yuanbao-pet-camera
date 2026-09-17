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
  console.log('DOM loaded, waiting for Flutter render (max 50s)...');

  let rendered = false;
  try {
    await page.waitForFunction(() => {
      if (document.querySelector('flt-glass-pane')) return true;
      if (document.querySelector('flutter-view')) return true;
      if (document.querySelector('.flutter-view')) return true;
      const t = document.body.innerText || '';
      if (t.includes('元宝') || t.includes('金元宝') || t.includes('小棉花') || t.includes('功能')) return true;
      return false;
    }, { timeout: 50000 });
    rendered = true;
  } catch (e) {
    rendered = false;
    console.log('wait timeout:', e.message);
  }

  console.log('RENDERED:', rendered);
  await page.screenshot({ path: 'F:/元宝爱拍照/pet_camera/build/verify.png' });
  const text = await page.evaluate(() => document.body.innerText).catch(() => '');
  console.log('BODY_TEXT:', JSON.stringify(text.slice(0, 400)));
  console.log('ERRORS:', errors.length ? errors.slice(0, 15).join(' || ') : 'none');
  await browser.close();
})().catch(e => { console.error('SCRIPT_FAIL:', e); process.exit(1); });
