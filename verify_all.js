const { chromium } = require('C:/Users/yuting.yang1/.workbuddy/binaries/node/workspace/node_modules/playwright');

(async () => {
  const browser = await chromium.launch();
  const page = await browser.newPage({ viewport: { width: 420, height: 920 } });
  const errors = [];
  page.on('console', (m) => { if (m.type() === 'error') errors.push(m.text()); });
  page.on('pageerror', (e) => errors.push('PAGEERROR: ' + e.message));

  const routes = ['/', '/#/camera', '/#/short-video', '/#/retouch', '/#/settings'];
  for (const r of routes) {
    errors.length = 0;
    try {
      await page.goto('http://localhost:8091/yuanbao-pet-camera' + r, { waitUntil: 'load', timeout: 60000 });
      await page.waitForSelector('flt-glass-pane', { state: 'attached', timeout: 60000 });
      await page.waitForTimeout(3500);
      console.log(r, '=> ERRORS:', JSON.stringify(errors.slice(0, 5)));
    } catch (e) {
      console.log(r, '=> NAV_ERROR:', e.message);
    }
  }
  await browser.close();
})();
