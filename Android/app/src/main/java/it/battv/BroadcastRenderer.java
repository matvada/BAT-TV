package it.battv;
import android.content.res.AssetManager;
import android.graphics.*;
import org.json.JSONObject;
import java.util.*;

/** Shared approved 320 × 118 design grid, painted directly into the video. */
final class BroadcastRenderer {
 private final AssetManager assets;
 BroadcastRenderer(AssetManager assets){this.assets=assets;}
 private Typeface broadcastFont;
 private final HashMap<String,Bitmap> crestCache=new HashMap<>();
 private Bitmap broadcastBat;
 private Bitmap broadcastAsset(String name){try(java.io.InputStream input=assets.open("broadcast/"+name+".png")){return BitmapFactory.decodeStream(input);}catch(java.io.IOException e){return null;}}
 private Bitmap broadcastCrest(String value){
  if(crestCache.containsKey(value))return crestCache.get(value);Bitmap image=null;
  if(value.matches("preset:(bat|hub|cbc|bin|vac|vbs|oli|rob|mi3|cat)"))image=broadcastAsset(value.substring(7));
  else if(value.startsWith("data:image/png;base64,")&&value.length()<=4600)try{byte[] bytes=android.util.Base64.decode(value.substring(22),android.util.Base64.DEFAULT);image=BitmapFactory.decodeByteArray(bytes,0,bytes.length);}catch(Exception ignored){}
  if(image!=null){if(crestCache.size()>24)crestCache.clear();crestCache.put(value,image);}return image;
 }
 private int mixColor(int a,int b,float f){return Color.rgb(Math.round(Color.red(a)*f+Color.red(b)*(1-f)),Math.round(Color.green(a)*f+Color.green(b)*(1-f)),Math.round(Color.blue(a)*f+Color.blue(b)*(1-f)));}
 private void broadcastPanel(Canvas c,Paint p,float x,float y,float w,float h,int[] colors,float[] stops,boolean bat){
  c.save();c.translate(x,y+h);c.skew(-.176327f,0);c.translate(0,-h);c.clipRect(0,0,w,h);
  p.setStyle(Paint.Style.FILL);p.setAlpha(255);p.setShader(new LinearGradient(0,0,0,h,colors,stops,Shader.TileMode.CLAMP));c.drawRect(0,0,w,h,p);p.setShader(null);
  if(bat&&broadcastBat!=null){p.setAlpha(92);p.setXfermode(new PorterDuffXfermode(PorterDuff.Mode.MULTIPLY));p.setFilterBitmap(true);c.drawBitmap(broadcastBat,null,new RectF(w*.1f,-h*.2f,w*1.15f,h*1.25f),p);p.setXfermode(null);p.setAlpha(255);}
  if(h==52){Path shine=new Path();shine.moveTo(81,0);shine.lineTo(120,0);shine.lineTo(97,52);shine.lineTo(58,52);shine.close();p.setColor(Color.argb(18,255,255,255));c.drawPath(shine,p);}
  p.setColor(Color.argb(143,255,255,255));c.drawRect(0,0,w,1,p);if(h==52){p.setColor(Color.argb(112,255,255,255));c.drawRect(0,50,w,52,p);}c.restore();
 }
 private void broadcastText(Canvas c,Paint p,String text,float x,float y,float w,float h,float size,Paint.Align edge,float padding){
  if(text.isEmpty())return;p.setTypeface(broadcastFont);p.setTextSkewX(-.176327f);p.setTextAlign(Paint.Align.LEFT);p.setTextSize(size);p.setColor(Color.WHITE);p.setAlpha(255);
  Rect bounds=new Rect();p.getTextBounds(text,0,text.length(),bounds);
  float factor=Math.min(1,Math.min((w-2*padding)/Math.max(1,bounds.width()),(h-4)/Math.max(1,bounds.height())));
  if(factor<1){p.setTextSize(size*factor);p.getTextBounds(text,0,text.length(),bounds);}
  float xx=edge==Paint.Align.LEFT?padding-bounds.left:edge==Paint.Align.RIGHT?w-padding-bounds.right:(w-bounds.width())/2-bounds.left;
  c.drawText(text,x+xx,y+(h-bounds.height())/2-bounds.top,p);p.setTextSkewX(0);
 }
 void draw(Canvas c,Paint p,JSONObject s,JSONObject h,JSONObject a,int remaining){
  if(broadcastFont==null)broadcastFont=Typeface.createFromAsset(assets,"broadcast/Galiga.ttf");if(broadcastBat==null)broadcastBat=broadcastAsset("watermark");
  c.save();float scale=1280*.205f/320*.9f;c.translate(1280*.115f,720*(1-.043f)-118*scale);c.scale(scale,scale);
  boolean homeLeft=s.optBoolean("homeOnLeft",true);
  drawBroadcastTeam(c,p,homeLeft?h:a,homeLeft,false);c.save();c.translate(155,0);drawBroadcastTeam(c,p,homeLeft?a:h,!homeLeft,true);c.restore();
  broadcastPanel(c,p,-.96f,87,303,30,new int[]{Color.rgb(75,77,78),Color.rgb(21,24,25),Color.rgb(9,11,13)},new float[]{0,.18f,1},false);
  int q=s.optInt("quarter",1);String quarter=q<=4?new String[]{"PRIMO QUARTO","SECONDO QUARTO","TERZO QUARTO","QUARTO QUARTO"}[Math.max(0,q-1)]:"SUPPLEMENTARE "+(q-4);
  broadcastText(c,p,quarter,14.489f,87,180,30,15,Paint.Align.LEFT,0);
  if(s.optBoolean("clockEnabled",true)){int r=remaining;broadcastText(c,p,String.format(Locale.US,"%02d:%02d",r/60,r%60),221.895f,87,70,30,19.2f,Paint.Align.RIGHT,0);}
  p.setTypeface(broadcastFont);p.setTextAlign(Paint.Align.LEFT);p.setTextSkewX(0);c.restore();
 }
 private void drawBroadcastTeam(Canvas c,Paint p,JSONObject team,boolean home,boolean right){
  int base=teamColor(team.optString("color"),Color.rgb(81,42,125));
  broadcastPanel(c,p,5,12,150,52,new int[]{mixColor(base,Color.WHITE,.76f),base,mixColor(base,Color.rgb(5,4,11),.45f)},new float[]{0,.08f,1},home);
  broadcastPanel(c,p,1.44f,66,150,19,new int[]{mixColor(base,Color.WHITE,.6f),base,mixColor(base,Color.BLACK,.55f)},new float[]{0,.13f,1},false);
  broadcastText(c,p,""+team.optInt("score"),9.584f,12,150,52,41,right?Paint.Align.LEFT:Paint.Align.RIGHT,12);
  broadcastText(c,p,"F",12.706f,66,10,19,11.84f,Paint.Align.CENTER,0);
  broadcastText(c,p,"TO",111.222f,66,16,19,11.84f,Paint.Align.CENTER,0);
  int[] counts={team.optInt("fouls"),team.optInt("timeouts")};float[] xs={26.222f,130.738f};
  for(int group=0;group<2;group++)for(int i=0;i<(group==0?5:3);i++){c.save();c.translate(xs[group]+i*4.96f,71.18f);c.skew(-.176327f,0);p.setColor(i<counts[group]?(home?Color.rgb(255,254,15):Color.WHITE):Color.argb(85,255,255,255));c.drawRect(0,0,2.88f,8.64f,p);c.restore();}
  float x=right?93.24f:17.808f;RectF rect=new RectF(x,0,x+60.8f,60.8f);c.save();Path circle=new Path();circle.addOval(rect,Path.Direction.CW);c.clipPath(circle);p.setColor(Color.WHITE);c.drawRect(rect,p);
  String value=team.optString("logo",home?"preset:bat":"");if(value.isEmpty()&&home)value="preset:bat";Bitmap image=broadcastCrest(value);
  if(image!=null){p.setFilterBitmap(true);c.drawBitmap(image,null,rect,p);}else broadcastText(c,p,team.optString("name").toUpperCase(Locale.ROOT),x+5,5,50.8f,50.8f,16,Paint.Align.CENTER,0);
  c.restore();p.setColor(Color.argb(128,255,255,255));p.setStyle(Paint.Style.STROKE);p.setStrokeWidth(1);c.drawOval(new RectF(x+.5f,.5f,x+60.3f,60.3f),p);p.setStyle(Paint.Style.FILL);
 }

 private int teamColor(String hex,int fallback){try{return hex.matches("#[0-9a-fA-F]{6}")?Color.parseColor(hex):fallback;}catch(Exception ignored){return fallback;}}
}
