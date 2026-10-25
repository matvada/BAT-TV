const {chromium}=require('playwright');const path=require('path');
(async()=>{const browser=await chromium.launch({args:['--no-sandbox']});
for(const platform of ['Android/app/src/main/assets','iPhone/COURTSIDE/BATWeb']){
 const page=await browser.newPage({viewport:{width:1024,height:768}});const errors=[];page.on('pageerror',e=>errors.push(String(e)));
 await page.goto('file://'+path.resolve(platform,'index.html'));
 await page.evaluate(()=>{window.sent=[];window.dispatch=o=>sent.push(o);receive({type:'role',role:'regia'});receive({type:'state',serverNow:Date.now(),state:{home:{name:'BAT',score:42,fouls:2,timeouts:1},away:{name:'VBA',score:40,fouls:3,timeouts:1},quarter:2,clock:60,running:false,board:{automatic:[],candidates:{homeScore:{value:42,at:Date.now()}}}}});remoteTab('board')});
 await page.locator('#board-homeScore button').click();if(await page.evaluate(()=>sent.length))throw Error('Enabled without review');
 await page.locator('#boardConfirm button').first().click();const cmd=await page.evaluate(()=>sent.at(-1));if(cmd.action!=='boardAuto'||JSON.parse(cmd.text).value!==42)throw Error('Wrong reviewed value');
 await page.locator('#boardStop').click();if(await page.evaluate(()=>sent.at(-1).text)!=='all')throw Error('Manual override missing');
 await page.evaluate(()=>{state.board.candidates.homeScore.at=Date.now()-5000;renderBoard()});if(!await page.locator('#board-homeScore button').isDisabled())throw Error('Stale reading allowed');
 await page.evaluate(()=>{receive({type:'role',role:'scores'});receive({type:'state',serverNow:Date.now(),state:{home:{name:'BAT',score:0},away:{name:'VBA',score:0},quarter:1,clock:600,running:false}});remoteTab('board')});
 if(!await page.locator('#readerSetup').isVisible())throw Error('Reader hidden');
 await page.locator('#readerSetup button').first().click();if(await page.evaluate(()=>sent.at(-1).type)!=='readerStart')throw Error('No native camera command');
 await page.setViewportSize({width:852,height:393});if(await page.evaluate(()=>{const p=document.querySelector('[data-remote-page="board"]');return p.scrollWidth>p.clientWidth+2}))throw Error('Reader overflow');
 if(errors.length)throw Error(errors.join('\n'));console.log('PASS board controls '+platform);await page.close();
}await browser.close()})().catch(e=>{console.error(e);process.exit(1)});
