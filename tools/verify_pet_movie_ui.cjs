// Compiled Flutter UI integration: use generated test footage, isolated profile.
const {chromium}=require('playwright');
const fs=require('node:fs');
const path=require('node:path');
(async()=>{
  const browser=await chromium.launch({channel:'chrome',headless:true});
  const context=await browser.newContext({viewport:{width:390,height:844},acceptDownloads:true});
  const page=await context.newPage();const errors=[];
  page.on('pageerror',e=>errors.push(e.message));
  async function visible(locator){
    for(let i=0;i<15;i++){
      const box=await locator.count() ? await locator.boundingBox({timeout:1000}) : null;
      if(box && box.y>=65 && box.y+box.height<820)return;
      await page.mouse.move(180,650);await page.mouse.wheel(0,box && box.y<65 ? -350 : 450);
      await page.waitForTimeout(120);
    }
    throw new Error('Cannot scroll to control: '+await locator.innerText());
  }
  try {
    await page.goto('http://127.0.0.1:8080/#/movie');await page.waitForTimeout(3500);
    const placeholder=page.locator('flt-semantics-placeholder');if(await placeholder.count())await placeholder.dispatchEvent('click');
    const chooser=page.waitForEvent('filechooser');
    await page.getByRole('button',{name:'选一段视频',exact:true}).click();
    await (await chooser).setFiles(path.resolve('.dart_tool/movie_verification/slideshow.mp4'));
    const marker=page.getByRole('button',{name:'标记这一刻',exact:true});await marker.waitFor({timeout:20000});
    await visible(marker);await marker.click({force:true});
    await page.getByText(/手动精彩标记/).waitFor();
    const encode=page.getByRole('button',{name:'制作并预览视频',exact:true});
    await visible(encode);await encode.click({force:true});
    await page.getByText('成片预览',{exact:true}).waitFor({timeout:45000});
    const save=page.getByRole('button',{name:'下载视频并加入我的短片',exact:true});
    await visible(save);
    fs.mkdirSync('.dart_tool/movie_verification',{recursive:true});
    await page.screenshot({path:'.dart_tool/movie_verification/pet_moment_ui.png'});
    const download=page.waitForEvent('download');await save.click({force:true});
    await (await download).saveAs('.dart_tool/movie_verification/ui_moment.mp4');
    if(errors.length)throw new Error(errors.join(';'));
    console.log(JSON.stringify({manualMoment:true,realSlowExport:true,pageErrors:errors}));
  } catch(e){
    console.log('UI_STATE',(await page.locator('body').innerText()).slice(-2400));
    await page.screenshot({path:'.dart_tool/movie_verification/pet_ui_failure.png'});throw e;
  } finally {await context.close();await browser.close();}
})().catch(e=>{console.error(e);process.exitCode=1;});
