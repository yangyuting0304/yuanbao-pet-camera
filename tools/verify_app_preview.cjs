// Isolated browser smoke check for the compiled local Flutter preview.
const { chromium } = require('playwright');
const fs = require('node:fs');
const path = require('node:path');
(async () => {
  const browser = await chromium.launch({channel:'chrome',headless:true});
  try {
    const context = await browser.newContext({viewport:{width:390,height:844},acceptDownloads:true});
    const page = await context.newPage();
    const errors=[]; page.on('pageerror',e=>{errors.push(e.message);console.log('PAGE_ERROR',e.message)});
    page.on('console',m=>console.log('CONSOLE',m.type(),m.text()));
    page.on('requestfailed',r=>console.log('REQUEST_FAIL',r.url(),r.failure()?.errorText));
    await page.goto('http://127.0.0.1:8080/#/movie');
    await page.waitForTimeout(4000);
    console.log('PAGE_STATE',await page.title(),(await page.locator('body').innerText()).slice(0,300));
    await page.screenshot({path:'.dart_tool/movie_verification/boot.png'});
    await page.locator('flutter-view').waitFor({timeout:30000});
    const placeholder=page.locator('flt-semantics-placeholder');
    if(await placeholder.count())await placeholder.dispatchEvent('click');
    await page.getByRole('button',{name:'选照片',exact:true}).waitFor({timeout:30000});
    const chooserPromise=page.waitForEvent('filechooser');
    await page.getByRole('button',{name:'选照片',exact:true}).click();
    const chooser=await chooserPromise;
    await chooser.setFiles(path.resolve('assets/brand/app_icon_yuanbao_cat.png'));
    const exportButton=page.getByRole('button',{name:'制作并预览视频',exact:true});
    await exportButton.waitFor();
    await page.waitForTimeout(1000);
    console.log('AFTER_PICK',(await page.locator('body').innerText()).slice(-2500));
    await page.screenshot({path:'.dart_tool/movie_verification/after_pick.png',fullPage:true});
    await exportButton.click();
    try { await page.getByText('成片预览',{exact:true}).waitFor({timeout:30000}); }
    catch(e) {
      console.log('EXPORT_STATE',(await page.locator('body').innerText()).slice(-2300));
      await page.screenshot({path:'.dart_tool/movie_verification/export_failure.png'});
      throw e;
    }
    fs.mkdirSync('.dart_tool/movie_verification',{recursive:true});
    await page.screenshot({path:'.dart_tool/movie_verification/editor.png',fullPage:true});
    // Flutter scrollables need real wheel input; DOM scrolling only moves semantics.
    await page.mouse.move(180,650);
    await page.mouse.wheel(0,1100);
    await page.waitForTimeout(700);
    await page.screenshot({path:'.dart_tool/movie_verification/save.png'});
    const downloaded=page.waitForEvent('download',{timeout:15000});
    await page.getByRole('button',{name:'下载视频并加入我的短片',exact:true}).click();
    await page.waitForTimeout(1000);
    console.log('AFTER_SAVE',(await page.locator('body').innerText()).slice(-1300));
    const download=await downloaded;
    await download.saveAs('.dart_tool/movie_verification/'+download.suggestedFilename());
    await page.reload();
    await page.locator('flutter-view').waitFor({timeout:60000});
    if(await placeholder.count())await placeholder.dispatchEvent('click');
    await page.getByRole('button',{name:'我的短片',exact:true}).click();
    await page.waitForTimeout(800);
    console.log('LIBRARY',(await page.locator('body').innerText()).slice(-1800));
    await page.screenshot({path:'.dart_tool/movie_verification/library.png'});
    await page.getByText(/萌宠短片/).first().waitFor({timeout:20000});
    console.log(JSON.stringify({editorExport:true,download:download.suggestedFilename(),librarySurvivesReload:true,pageErrors:errors}));
    await context.close();
  } finally { await browser.close(); }
})().catch(e=>{console.error(e);process.exitCode=1;});
