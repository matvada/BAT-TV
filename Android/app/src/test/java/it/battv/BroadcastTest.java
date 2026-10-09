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
 @Test public void nativeRenderingFitsFrame()throws Exception{
  BroadcastRenderer renderer=new BroadcastRenderer(RuntimeEnvironment.getApplication().getAssets());GameStore g=new GameStore();g.apply(command("preset","opponentPreset","hub"));g.state.getJSONObject("home").put("score",32).put("fouls",2).put("timeouts",1);g.state.getJSONObject("away").put("score",28).put("fouls",3);
  render(renderer,g,"broadcast-home-left");
  g.state.put("homeOnLeft",false).put("clockEnabled",false).put("quarter",3);g.state.getJSONObject("home").put("score",128);render(renderer,g,"broadcast-home-right-clock-off");
  g.state.put("homeOnLeft",true).put("clockEnabled",true).put("quarter",12).put("clock",3600);g.state.getJSONObject("home").put("score",999);g.state.getJSONObject("away").put("score",999).put("logo","preset:cat");render(renderer,g,"broadcast-long-labels");
 }
 private void render(BroadcastRenderer renderer,GameStore g,String name)throws Exception{
  Bitmap bitmap=Bitmap.createBitmap(1920,1080,Bitmap.Config.ARGB_8888);Canvas c=new Canvas(bitmap);c.scale(1.5f,1.5f);Paint p=new Paint(Paint.ANTI_ALIAS_FLAG);
  renderer.draw(c,p,g.state,g.state.getJSONObject("home"),g.state.getJSONObject("away"),g.remaining());
  assertEquals("Watermark must preserve opaque panel",255,Color.alpha(bitmap.getPixel(430,960)));
  int minX=1920,minY=1080,maxX=0,maxY=0;for(int y=0;y<1080;y++)for(int x=0;x<1920;x++)if(Color.alpha(bitmap.getPixel(x,y))>0){minX=Math.min(x,minX);minY=Math.min(y,minY);maxX=Math.max(x,maxX);maxY=Math.max(y,maxY);}
  assertTrue("Graphic must stay in its approved frame",minX>=210&&maxX<=590&&minY>=895&&maxY<=1040);
  assertTrue("Graphic is empty",maxX-minX>300&&maxY-minY>100);
  File dir=new File("build/native-render-check");dir.mkdirs();try(FileOutputStream out=new FileOutputStream(new File(dir,name+".png"))){bitmap.compress(Bitmap.CompressFormat.PNG,100,out);}
 }
}
