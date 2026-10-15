package it.battv;
import static org.junit.Assert.*;
import android.graphics.*;
import org.json.JSONObject;
import org.junit.Test;
import org.junit.runner.RunWith;
import org.robolectric.RobolectricTestRunner;
import org.robolectric.RuntimeEnvironment;
import org.robolectric.annotation.Config;
import org.robolectric.annotation.GraphicsMode;
import java.io.*;

@RunWith(RobolectricTestRunner.class)
@Config(sdk=35)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
public class BroadcastTest {
 @Test public void audioResamplingPreservesDurationAndLevel(){
  byte[] pcm=new byte[64000];for(int i=0;i<pcm.length;i+=2){pcm[i]=(byte)0xe8;pcm[i+1]=3;}
  byte[] result=Soundboard.resample48k(pcm);assertEquals(96000,result.length);
  for(int i=0;i<result.length;i+=2)assertEquals(1000,(short)((result[i]&255)|(result[i+1]<<8)));
  assertEquals(0,Soundboard.resample48k(new byte[0]).length);
 }
 private JSONObject command(String id,String action,String text)throws Exception{return new JSONObject().put("id",id).put("action",action).put("text",text);}
 @Test public void presetAndManualPreserveMatch()throws Exception{
  GameStore g=new GameStore();g.state.getJSONObject("away").put("score",28).put("fouls",3);g.state.put("quarter",2);
  assertTrue(g.apply(command("preset","opponentPreset","vac")));
  JSONObject a=g.state.getJSONObject("away");assertEquals("VBA",a.getString("name"));assertEquals("preset:vac",a.getString("logo"));assertEquals(28,a.getInt("score"));assertEquals(3,a.getInt("fouls"));assertEquals(2,g.state.getInt("quarter"));
  assertFalse(g.apply(command("invalid","opponentPreset","unknown")));
  assertTrue(g.apply(command("manual","opponentPreset","manual")));a=g.state.getJSONObject("away");assertEquals("",a.getString("name"));assertEquals("",a.getString("logo"));assertEquals(28,a.getInt("score"));
  assertFalse(g.apply(command("badLogo","teamLogo","preset:../../Info").put("team","home")));
  assertTrue(g.apply(command("batLogo","teamLogo","preset:bat").put("team","home")));
 }
 @Test public void positionCommandPreservesMatch()throws Exception{
  GameStore g=new GameStore();g.state.getJSONObject("home").put("score",32);
  assertEquals("left",g.state.getString("scorePosition"));
  assertTrue(g.apply(command("center","scorePosition","center")));assertEquals("center",g.state.getString("scorePosition"));assertEquals(32,g.state.getJSONObject("home").getInt("score"));
  assertFalse(g.apply(command("bad","scorePosition","top")));assertEquals("center",g.state.getString("scorePosition"));
 }
 @Test public void broadcastCardsFitAndGlitterAnimates()throws Exception{
  BroadcastRenderer renderer=new BroadcastRenderer(RuntimeEnvironment.getApplication().getAssets());GameStore g=new GameStore();g.state.getJSONObject("home").put("score",32);g.state.getJSONObject("away").put("score",28);g.state.put("caption","UN TITOLO MOLTO LUNGO DA CONTENERE NEL CARTELLO");
  for(String kind:new String[]{"kiss","glitter","timeout","triple","cheer","break","final","caption"}){
   assertTrue(g.apply(command(kind,"overlay",kind).put("value",15)));
   for(int[] viewport:new int[][]{{852,393},{1024,768},{1280,720}}){
    renderer.setViewport(viewport[0],viewport[1]);RectF visible=new RectF(0,0,1280,720);Bitmap b=Bitmap.createBitmap(1280,720,Bitmap.Config.ARGB_8888);renderer.drawCard(new Canvas(b),new Paint(Paint.ANTI_ALIAS_FLAG),g.state,kind,1000);
    int pixels=0;for(int y=0;y<720;y++)for(int x=0;x<1280;x++)if(Color.alpha(b.getPixel(x,y))>0){pixels++;assertTrue("Card cropped",visible.contains(x,y));}assertTrue("Empty card",pixels>1000);
    if(viewport[0]==852){File dir=new File("build/native-render-check");dir.mkdirs();try(FileOutputStream out=new FileOutputStream(new File(dir,"card-"+kind+".png"))){b.compress(Bitmap.CompressFormat.PNG,100,out);}}
   }
  }
  Bitmap a=Bitmap.createBitmap(1280,720,Bitmap.Config.ARGB_8888),b=Bitmap.createBitmap(1280,720,Bitmap.Config.ARGB_8888);renderer.drawCard(new Canvas(a),new Paint(),g.state,"glitter",1000);renderer.drawCard(new Canvas(b),new Paint(),g.state,"glitter",1200);assertFalse("Glitter must animate",a.sameAs(b));
 }
 @Test public void nativeRenderingFitsFrame()throws Exception{
  BroadcastRenderer renderer=new BroadcastRenderer(RuntimeEnvironment.getApplication().getAssets());GameStore g=new GameStore();g.apply(command("preset","opponentPreset","hub"));g.state.getJSONObject("home").put("score",32).put("fouls",2).put("timeouts",1);g.state.getJSONObject("away").put("score",28).put("fouls",3);
  render(renderer,g,"broadcast-home-left");
  g.state.put("homeOnLeft",false).put("clockEnabled",false).put("quarter",3);g.state.getJSONObject("home").put("score",128);render(renderer,g,"broadcast-home-right-clock-off");
  g.state.put("homeOnLeft",true).put("clockEnabled",true).put("quarter",12).put("clock",3600);g.state.getJSONObject("home").put("score",999);g.state.getJSONObject("away").put("score",999).put("logo","preset:cat");render(renderer,g,"broadcast-long-labels");
 }
 @Test public void widePhoneAndTabletKeepEntireOverlayVisible()throws Exception{
  BroadcastRenderer renderer=new BroadcastRenderer(RuntimeEnvironment.getApplication().getAssets());GameStore g=new GameStore();
  for(String position:new String[]{"left","center","right"})for(int[] viewport:new int[][]{{852,393},{1024,768},{1280,720}}){
   assertTrue(g.apply(command(position+viewport[0],"scorePosition",position)));
   renderer.setViewport(viewport[0],viewport[1]);RectF visible=new RectF(0,0,1280,720);
   Bitmap b=Bitmap.createBitmap(1280,720,Bitmap.Config.ARGB_8888);Canvas c=new Canvas(b);Paint p=new Paint(Paint.ANTI_ALIAS_FLAG);
   renderer.draw(c,p,g.state,g.state.getJSONObject("home"),g.state.getJSONObject("away"),600);
   int minX=1280,maxX=0;
   for(int y=0;y<720;y++)for(int x=0;x<1280;x++)if(Color.alpha(b.getPixel(x,y))>0){minX=Math.min(minX,x);maxX=Math.max(maxX,x);assertTrue("Graphic cropped by preview",x>=visible.left&&x<=visible.right&&y>=visible.top&&y<=visible.bottom);}
   if(position.equals("center"))assertEquals("Graphic centred",visible.centerX(),(minX+maxX)/2f,2f);
   if(position.equals("right"))assertEquals("Right margin matches left margin",visible.width()*.03f,visible.right-maxX,2f);
   float logoX=visible.left+visible.width()*.917f,logoY=visible.top+visible.height()*.03f,logoWidth=visible.width()*.053f;
   assertTrue(logoX>=visible.left&&logoX+logoWidth<=visible.right&&logoY>=visible.top&&logoY+logoWidth<=visible.bottom);
  }
 }
 private void render(BroadcastRenderer renderer,GameStore g,String name)throws Exception{
  Bitmap bitmap=Bitmap.createBitmap(1920,1080,Bitmap.Config.ARGB_8888);Canvas c=new Canvas(bitmap);c.scale(1.5f,1.5f);Paint p=new Paint(Paint.ANTI_ALIAS_FLAG);
  renderer.draw(c,p,g.state,g.state.getJSONObject("home"),g.state.getJSONObject("away"),g.remaining());
  assertEquals("Watermark must preserve opaque panel",255,Color.alpha(bitmap.getPixel(150,950)));
  int minX=1920,minY=1080,maxX=0,maxY=0;for(int y=0;y<1080;y++)for(int x=0;x<1920;x++)if(Color.alpha(bitmap.getPixel(x,y))>0){minX=Math.min(x,minX);minY=Math.min(y,minY);maxX=Math.max(x,maxX);maxY=Math.max(y,maxY);}
  assertTrue("Graphic must stay in its approved frame",minX>=55&&maxX<=510&&minY>=875&&maxY<=1050);
  assertTrue("Graphic is empty",maxX-minX>300&&maxY-minY>100);
  File dir=new File("build/native-render-check");dir.mkdirs();try(FileOutputStream out=new FileOutputStream(new File(dir,name+".png"))){bitmap.compress(Bitmap.CompressFormat.PNG,100,out);}
 }
}
