// Run with Playwright available and CHROMIUM_PATH set to a local Chromium binary.
const {chromium}=require('playwright');
const path=require('path');
(async()=>{
 const browser=await chromium.launch({executablePath:process.env.CHROMIUM_PATH,args:['--no-sandbox','--disable-gpu','--disable-dev-shm-usage']});
 for(const platform of ['iPhone/COURTSIDE/BATWeb','Android/app/src/main/assets'])for(const [width,height] of [[852,393],[1536,709],[1024,768]]){
  const page=await browser.newPage({viewport:{width,height},hasTouch:true});
  await page.goto('file://'+path.resolve(__dirname,'..',platform,'index.html'));
  await page.evaluate(()=>{receive({type:'role',role:'camera'});document.body.classList.add('cameraActive');toggleCameraControls(true)});
  const w=Math.min(width,height*16/9),h=w*9/16;
  const x=(width-w)/2+w*.9435,y=(height-h)/2+h*.03+w*.0265;
  const hit=await page.evaluate(({x,y})=>{const e=document.getElementById('showCameraControls'),r=e.getBoundingClientRect();return Math.abs((r.left+r.right)/2-x)<1&&Math.abs((r.top+r.bottom)/2-y)<1&&r.width>=60&&document.elementFromPoint(x,y)===e},{x,y});
  if(!hit)throw Error(platform+': menu is not aligned to the aspect-fit logo');
  await page.touchscreen.tap(x,y);
  if(await page.evaluate(()=>document.body.classList.contains('cameraClean')))throw Error('Menu did not open');
  console.log('PASS '+platform+' '+width+'x'+height);await page.close();
 }
 await browser.close();
})().catch(e=>{console.error(e);process.exit(1)});
