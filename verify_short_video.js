const { chromium } = require('C:/Users/yuting.yang1/.workbuddy/binaries/node/workspace/node_modules/playwright');

(async () => {
  const browser = await chromium.launch();
  const page = await browser.newPage({ viewport: { width: 420, height: 920 } });
  page.on('console', (m) => { console.log('CONSOLE['+m.type()+']:', m.text()); });
  page.on('pageerror', (e) => { console.log('PAGEERROR_FULL:', e.message, '\nSTACK:', e.stack || '(no stack)'); });

  try {
    await page.goto('http://localhost:8091/yuanbao-pet-camera/#/short-video', { waitUntil: 'load', timeout: 60000 });
    await page.waitForSelector('flt-glass-pane', { state: 'attached', timeout: 60000 });
    await page.waitForTimeout(6000);
    await page.screenshot({ path: 'F:/元宝爱拍照/pet_camera/short_video_verify.png' });
    console.log('SHOT_OK');
  } catch (e) {
    console.log('NAV_ERROR:', e.message);
  }
  await browser.close();
})();
