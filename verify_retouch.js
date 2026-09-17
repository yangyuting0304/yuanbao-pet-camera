const { chromium } = require('C:/Users/yuting.yang1/.workbuddy/binaries/node/workspace/node_modules/playwright');

(async () => {
  const browser = await chromium.launch();
  const page = await browser.newPage({ viewport: { width: 420, height: 920 } });
  const errors = [];
  page.on('console', (m) => { if (m.type() === 'error') errors.push(m.text()); });
  page.on('pageerror', (e) => errors.push('PAGEERROR: ' + e.message));

  try {
    await page.goto('http://localhost:8091/yuanbao-pet-camera/#/retouch', { waitUntil: 'load', timeout: 60000 });
    await page.waitForSelector('flt-glass-pane', { state: 'attached', timeout: 60000 });
    await page.waitForTimeout(6000);
    const text = await page.evaluate(() => document.body.innerText).catch(() => '');
    console.log('HAS_TITLE:', text.includes('宠物 P 图'));
    console.log('HAS_FILTER:', text.includes('滤镜'));
    console.log('HAS_STICKER:', text.includes('贴纸'));
    console.log('HAS_BG:', text.includes('背景'));
    console.log('HAS_SHAPE:', text.includes('形状'));
    await page.screenshot({ path: 'F:/元宝爱拍照/pet_camera/retouch_verify.png' });
    console.log('SHOT_OK');

    // 尝试点击滤镜标签，确认交互不崩
    const tabFilter = await page.locator('text=滤镜').first();
    if (await tabFilter.count()) { await tabFilter.click(); await page.waitForTimeout(800); }
    const tabSticker = await page.locator('text=贴纸').first();
    if (await tabSticker.count()) { await tabSticker.click(); await page.waitForTimeout(800); }
    await page.screenshot({ path: 'F:/元宝爱拍照/pet_camera/retouch_verify2.png' });
    console.log('INTERACT_OK');
  } catch (e) {
    console.log('NAV_ERROR:', e.message);
  }
  console.log('ERRORS:', JSON.stringify(errors.slice(0, 8)));
  await browser.close();
})();
