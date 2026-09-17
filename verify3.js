const { chromium } = require('playwright');

(async () => {
  const browser = await chromium.launch({
    executablePath: 'C:\\Program Files\\Google\\Chrome\\Application\\chrome.exe',
    args: ['--no-sandbox', '--disable-dev-shm-usage', '--enable-webgl'],
    headless: true
  });
  const page = await browser.newPage({ viewport: { width: 1200, height: 900 } });

  const allLogs = [];
  page.on('console', m => {
    allLogs.push(`[${m.type()}] ${m.text().slice(0, 200)}`);
  });
  page.on('pageerror', e => allLogs.push(`[PAGEERROR] ${e.message.slice(0, 200)}`));
  page.on('requestfailed', req => allLogs.push(`[REQ_FAIL] ${req.url().slice(0, 100)} - ${req.failure().errorText}`));

  console.log('Loading page...');
  await page.goto('http://localhost:8101/yuanbao-pet-camera/', { waitUntil: 'domcontentloaded', timeout: 60000 });

  console.log('Waiting 70 seconds for render...');
  await new Promise(r => setTimeout(r, 70000));

  // 截图
  await page.screenshot({ path: 'F:/元宝爱拍照/pet_camera/build/verify3.png' });

  // DOM 状态
  const domInfo = await page.evaluate(() => {
    const glass = document.querySelector('flt-glass-pane');
    return {
      glassExists: !!glass,
      glassHTML: glass ? glass.innerHTML.slice(0, 500) : null,
      glassVisible: glass ? getComputedStyle(glass).display !== 'none' : false,
      bodyChildCount: document.body.children.length,
      bodyTags: Array.from(document.body.children).map(c =>
        c.tagName + (c.id ? '#' + c.id : '') + (c.className ? '.' + c.className : '')
      ).join(' | '),
      bodyText: document.body.innerText.slice(0, 300)
    };
  });

  console.log('\n=== DOM STATE ===');
  console.log(JSON.stringify(domInfo, null, 2));

  console.log('\n=== ALL LOGS (' + allLogs.length + ') ===');
  allLogs.forEach(l => console.log(l));

  if (allLogs.length === 0) console.log('(no logs at all - completely silent)');

  await browser.close();
})().catch(e => { console.error('FAIL:', e); process.exit(1); });
