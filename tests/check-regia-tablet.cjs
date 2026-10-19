// NODE_PATH must include Playwright; CHROMIUM_PATH selects a local browser.
const {chromium}=require('playwright');
const path=require('path');
(async()=>{
 const browser=await chromium.launch({executablePath:process.env.CHROMIUM_PATH,args:['--no-sandbox','--disable-gpu','--disable-dev-shm-usage']});
 for(const platform of ['iPhone/COURTSIDE/BATWeb','Android/app/src/main/assets']){
  for(const [width,height] of [[1024,768],[1180,820],[1280,800],[960,600],[768,1024],[852,393]]){
   const page=await browser.newPage({viewport:{width,height},hasTouch:true});
   await page.goto('file://'+path.resolve(__dirname,'..',platform,'index.html'));
   await page.evaluate(()=>{
    window.sent=[];window.dispatch=o=>sent.push(o);
    receive({type:'role',role:'regia'});
    receive({type:'state',serverNow:Date.now(),publishing:true,state:{home:{name:'BAT',score:38,fouls:3,timeouts:1},away:{name:'VBA',score:42,fouls:2,timeouts:2},quarter:2,clock:323,running:false,clockEnabled:true}});
   });
   for(const tab of ['score','time','broadcast']){
    await page.evaluate(tab=>remoteTab(tab),tab);
    const problems=await page.evaluate(({height})=>{
     const root=document.querySelector('.remotePage:not(.hidden)');
     const errors=[];
     if(root.scrollWidth>root.clientWidth+2)errors.push('horizontal overflow');
     const tablet=innerWidth>=700&&height>=550;
     for(const b of [...root.querySelectorAll('button,input,select'),...document.querySelectorAll('#remoteTabs button')]){
      if(!b.getClientRects().length||b.closest('.hidden'))continue;
      const r=b.getBoundingClientRect(),s=getComputedStyle(b);
      if(r.height<(tablet?55:43)||(b.type!=='color'&&parseFloat(s.fontSize)<(tablet?20:16)))errors.push('small control '+b.textContent);
      if(b.scrollWidth>b.clientWidth+2 && b.tagName==='BUTTON')errors.push('clipped text '+b.textContent);
     }
     return errors;
    },{height});
    if(problems.length)throw Error(platform+' '+width+'x'+height+' '+tab+': '+problems.join('; '));
   }
   await page.evaluate(()=>remoteTab('score'));
   for(const cue of ['horn','crowd','drums']){
    await page.locator('.soundBar button').nth(['horn','crowd','drums'].indexOf(cue)).click();
    const sent=await page.evaluate(()=>window.sent.at(-1));
    if(sent.action!=='sound'||sent.text!==cue)throw Error('Incorrect sound command');
   }
   if(process.env.REGIA_SCREENSHOT && width===1024&&platform.startsWith('iPhone')){
    await page.evaluate(()=>document.querySelector('.scorePage').scrollTop=0);
    await page.screenshot({path:process.env.REGIA_SCREENSHOT});
   }
   await page.evaluate(()=>receive({type:'role',role:'camera'}));
   if(await page.evaluate(()=>document.body.classList.contains('regiaMode')))throw Error('Regia style leaked into Camera');
   console.log('PASS '+platform+' '+width+'x'+height);await page.close();
  }
 }
 await browser.close();
})().catch(e=>{console.error(e);process.exit(1)});
