package it.battv;
import android.content.res.AssetManager;
import android.graphics.*;
import org.json.JSONObject;
import java.util.*;

/** Shared approved 320 × 118 design grid, painted directly into the video. */
final class BroadcastRenderer {
 private final AssetManager assets;
 private RectF visibleRect=new RectF(0,0,1280,720);
 static RectF visibleVideoRect(int width,int height){
  if(width<=0||height<=0)return new RectF(0,0,1280,720);
  float scale=Math.max(width/1280f,height/720f),w=width/scale,h=height/scale;
  return new RectF((1280-w)/2,(720-h)/2,(1280+w)/2,(720+h)/2);
 }
 void setViewport(int width,int height){visibleRect=new RectF(0,0,1280,720);}
 BroadcastRenderer(AssetManager assets){this.assets=assets;}
 private Typeface broadcastFont;
 private Bitmap kissArtwork;
 void drawCard(Canvas c,Paint p,JSONObject s,String kind,long now){
  if(kind.isEmpty())return;
  if(broadcastFont==null)broadcastFont=Typeface.createFromAsset(assets,"broadcast/Galiga.ttf");
  if(broadcastBat==null)broadcastBat=broadcastAsset("watermark");
  float scale=Math.min(visibleRect.width()*.78f/1000,visibleRect.height()*.70f/480);
  boolean framed=kind.equals("kiss")||kind.equals("glitter");
  c.save();c.translate(visibleRect.centerX()-500*scale,visibleRect.centerY()-(framed?280:240)*scale);c.scale(scale,scale);
  int[] purple={Color.rgb(105,60,149),Color.rgb(81,42,125),Color.rgb(35,15,58)};
  if(kind.equals("kiss")||kind.equals("glitter")){
   Path frame=new Path();frame.moveTo(65,25);frame.lineTo(975,25);frame.lineTo(935,455);frame.lineTo(25,455);frame.close();
   p.setStyle(Paint.Style.STROKE);p.setColor(Color.argb(217,81,42,125));p.setStrokeWidth(18);c.drawPath(frame,p);p.setColor(Color.rgb(255,254,15));p.setStrokeWidth(4);c.drawPath(frame,p);p.setStyle(Paint.Style.FILL);
   if(kind.equals("kiss")){
    float[][] hearts={{67,35,19,-.25f},{97,21,12,.2f},{948,20,12,-.2f},{972,40,19,.25f},{52,155,12,-.2f},{38,300,13,-.15f},{958,170,12,.2f},{945,310,15,.15f},{30,438,19,-.2f},{64,445,12,.15f},{906,445,12,-.15f},{938,438,19,.2f}};
    for(float[] heart:hearts)drawHeart(c,p,heart[0],heart[1],heart[2],heart[3]);
    broadcastPanel(c,p,165,365,670,82,purple,new float[]{0,.4f,1},false);
    p.setColor(Color.rgb(255,254,15));c.drawRect(179.46f,365,849.46f,367,p);
    broadcastText(c,p,"KISS",200,370,185,70,84,Paint.Align.CENTER,14);broadcastText(c,p,"CAM",615,370,185,70,84,Paint.Align.CENTER,14);
    if(kissArtwork==null)kissArtwork=broadcastAsset("kiss-crest");
    if(kissArtwork!=null){p.setColor(Color.WHITE);p.setAlpha(255);p.setFilterBitmap(true);float height=230f*kissArtwork.getHeight()/kissArtwork.getWidth();c.drawBitmap(kissArtwork,null,new RectF(385,455-height,615,455),p);}
   }else for(int i=0;i<90;i++){
    float x=(i*137+53)%930+35,y=(i*97+19)%420+30,pulse=(float)(.5+.5*Math.sin(now/240.0+i*1.7)),r=2+pulse*(i%4+2);
    p.setColor(i%3==0?Color.rgb(255,254,15):Color.WHITE);p.setAlpha(Math.round((.25f+pulse*.75f)*255));
    Path star=new Path();star.moveTo(x,y-r*2);star.lineTo(x+r*.45f,y-r*.45f);star.lineTo(x+r*2,y);star.lineTo(x+r*.45f,y+r*.45f);star.lineTo(x,y+r*2);star.lineTo(x-r*.45f,y+r*.45f);star.lineTo(x-r*2,y);star.lineTo(x-r*.45f,y-r*.45f);star.close();c.drawPath(star,p);
   }
   if(!kind.equals("kiss")){cardPanel(c,p,245,365,510,75,purple);
   broadcastText(c,p,"GLITTER CAM",260,370,480,60,65,Paint.Align.CENTER,14);}
  }else{
   String title=kind.equals("timeout")?"TIMEOUT":kind.equals("break")?"INTERVALLO":kind.equals("final")?"FINE PARTITA":kind.equals("triple")?"+3  TRIPLA!":kind.equals("cheer")?"FORZA BAT!":s.optString("caption");
   cardPanel(c,p,110,145,780,175,purple);
   broadcastPanel(c,p,110-65*.176327f,320,780,65,new int[]{Color.BLACK,Color.rgb(41,41,41)},new float[]{0,1},false);
   broadcastText(c,p,title,135,160,730,135,kind.equals("caption")?58:96,Paint.Align.CENTER,14);
   JSONObject left=s.optJSONObject(s.optBoolean("homeOnLeft",true)?"home":"away"),right=s.optJSONObject(s.optBoolean("homeOnLeft",true)?"away":"home");
   String footer=Arrays.asList("timeout","break","final").contains(kind)?left.optString("name")+"  "+left.optInt("score")+" – "+right.optInt("score")+"  "+right.optString("name"):kind.equals("triple")?"BOMBA DA TRE":kind.equals("cheer")?"TUTTI INSIEME":"BAT TV";
   broadcastText(c,p,footer,135,327,730,52,46,Paint.Align.CENTER,14);
  }
  p.setAlpha(255);p.setTextSkewX(0);p.setStyle(Paint.Style.FILL);c.restore();
 }
 private final HashMap<String,Bitmap> crestCache=new HashMap<>();
 private void drawHeart(Canvas c,Paint p,float x,float y,float radius,float angle){
  c.save();c.translate(x,y);c.rotate((float)Math.toDegrees(angle));c.scale(radius,radius);
  Path h=new Path();h.moveTo(0,.88f);h.cubicTo(-.3f,.58f,-.95f,.2f,-.95f,-.25f);h.cubicTo(-.95f,-.95f,-.3f,-1,0,-.58f);h.cubicTo(.3f,-1,.95f,-.95f,.95f,-.25f);h.cubicTo(.95f,.2f,.3f,.58f,0,.88f);h.close();
  p.setStyle(Paint.Style.FILL);p.setColor(Color.rgb(100,22,164));c.drawPath(h,p);p.setStyle(Paint.Style.STROKE);p.setColor(Color.rgb(195,125,247));p.setStrokeWidth(.16f);c.drawPath(h,p);p.setStyle(Paint.Style.FILL);c.restore();
 }
 private Bitmap broadcastBat;
 private void cardPanel(Canvas c,Paint p,float x,float y,float w,float h,int[] colors){
  broadcastPanel(c,p,x,y,w,h,colors,new float[]{0,.4f,1},false);
  if(broadcastBat==null)return;c.save();float inset=h*.176327f;
  Path clip=new Path();clip.moveTo(x+inset,y);clip.lineTo(x+w+inset,y);clip.lineTo(x+w,y+h);clip.lineTo(x,y+h);clip.close();c.clipPath(clip);
  float height=h*1.25f,width=height*broadcastBat.getWidth()/broadcastBat.getHeight();
  p.setAlpha(77);p.setFilterBitmap(true);c.drawBitmap(broadcastBat,null,new RectF(x+w*.68f-width/2,y+h/2-height/2,x+w*.68f+width/2,y+h/2+height/2),p);p.setAlpha(255);c.restore();
 }
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
  if(bat&&broadcastBat!=null){p.setAlpha(92);p.setXfermode(null);p.setFilterBitmap(true);c.drawBitmap(broadcastBat,null,new RectF(w*.1f,-h*.2f,w*1.15f,h*1.25f),p);p.setXfermode(null);p.setAlpha(255);}
  if(h==52){Path shine=new Path();shine.moveTo(81,0);shine.lineTo(120,0);shine.lineTo(97,52);shine.lineTo(58,52);shine.close();p.setColor(Color.argb(18,255,255,255));c.drawPath(shine,p);}
  p.setColor(Color.argb(143,255,255,255));c.drawRect(0,0,w,1,p);if(h==52){p.setColor(Color.argb(112,255,255,255));c.drawRect(0,50,w,52,p);}c.restore();
 }
 private void broadcastText(Canvas c,Paint p,String text,float x,float y,float w,float h,float size,Paint.Align edge,float padding){
  broadcastText(c,p,text,x,y,w,h,size,edge,padding,Color.WHITE);
 }
 private void broadcastText(Canvas c,Paint p,String text,float x,float y,float w,float h,float size,Paint.Align edge,float padding,int ink){
  if(text.isEmpty())return;p.setTypeface(broadcastFont);p.setTextSkewX(-.176327f);p.setTextAlign(Paint.Align.LEFT);p.setTextSize(size);p.setColor(ink);p.setAlpha(255);
  Rect bounds=new Rect();p.getTextBounds(text,0,text.length(),bounds);
  float factor=Math.min(1,Math.min((w-2*padding)/Math.max(1,bounds.width()),(h-4)/Math.max(1,bounds.height())));
  if(factor<1){p.setTextSize(size*factor);p.getTextBounds(text,0,text.length(),bounds);}
  float xx=edge==Paint.Align.LEFT?padding-bounds.left:edge==Paint.Align.RIGHT?w-padding-bounds.right:(w-bounds.width())/2-bounds.left;
  c.drawText(text,x+xx,y+(h-bounds.height())/2-bounds.top,p);p.setTextSkewX(0);
 }
 void draw(Canvas c,Paint p,JSONObject s,JSONObject h,JSONObject a,int remaining){
  if(broadcastFont==null)broadcastFont=Typeface.createFromAsset(assets,"broadcast/Galiga.ttf");if(broadcastBat==null)broadcastBat=broadcastAsset("watermark");
  c.save();float scale=visibleRect.width()*.205f/320*1.091475f;float x=visibleRect.left+visibleRect.width()*.03f;String position=s.optString("scorePosition","left");
  if(position.equals("center"))x=visibleRect.centerX()-160*scale;else if(position.equals("right"))x=visibleRect.right-visibleRect.width()*.03f-320*scale;
  c.translate(x,visibleRect.bottom-visibleRect.height()*.03f-118*scale);c.scale(scale,scale);
  boolean homeLeft=s.optBoolean("homeOnLeft",true);
  drawBroadcastTeam(c,p,homeLeft?h:a,homeLeft,false,s.optBoolean("showTeamLogos",true));c.save();c.translate(155,0);drawBroadcastTeam(c,p,homeLeft?a:h,!homeLeft,true,s.optBoolean("showTeamLogos",true));c.restore();
  broadcastPanel(c,p,-.96f,87,303,30,new int[]{Color.rgb(75,77,78),Color.rgb(21,24,25),Color.rgb(9,11,13)},new float[]{0,.18f,1},false);
  int q=s.optInt("quarter",1);String quarter=q<=4?new String[]{"PRIMO QUARTO","SECONDO QUARTO","TERZO QUARTO","QUARTO QUARTO"}[Math.max(0,q-1)]:"SUPPLEMENTARE "+(q-4);
  broadcastText(c,p,quarter,14.489f,87,180,30,15,Paint.Align.LEFT,0);
  if(s.optBoolean("clockEnabled",true)){int r=remaining;broadcastText(c,p,String.format(Locale.US,"%02d:%02d",r/60,r%60),221.895f,87,70,30,19.2f,Paint.Align.RIGHT,0);}
  p.setTypeface(broadcastFont);p.setTextAlign(Paint.Align.LEFT);p.setTextSkewX(0);c.restore();
 }
 private void drawBroadcastTeam(Canvas c,Paint p,JSONObject team,boolean home,boolean right,boolean showLogos){
  int base=teamColor(team.optString("color"),Color.rgb(81,42,125));
  broadcastPanel(c,p,5,12,150,52,new int[]{mixColor(base,Color.WHITE,.76f),base,mixColor(base,Color.rgb(5,4,11),.45f)},new float[]{0,.08f,1},home);
  broadcastPanel(c,p,1.44f,66,150,19,new int[]{mixColor(base,Color.WHITE,.6f),base,mixColor(base,Color.BLACK,.55f)},new float[]{0,.13f,1},false);
  broadcastText(c,p,""+team.optInt("score"),9.584f,12,150,52,41,right?Paint.Align.LEFT:Paint.Align.RIGHT,12);
  broadcastText(c,p,"F",12.706f,66,10,19,11.84f,Paint.Align.CENTER,0);
  broadcastText(c,p,"TO",111.222f,66,16,19,11.84f,Paint.Align.CENTER,0);
  int[] counts={team.optInt("fouls"),team.optInt("timeouts")};float[] xs={26.222f,130.738f};
  for(int group=0;group<2;group++)for(int i=0;i<(group==0?5:3);i++){c.save();c.translate(xs[group]+i*4.96f,71.18f);c.skew(-.176327f,0);p.setColor(i<counts[group]?(home?Color.rgb(255,254,15):Color.WHITE):Color.argb(85,255,255,255));c.drawRect(0,0,2.88f,8.64f,p);c.restore();}
  float x=right?93.24f:17.808f;RectF rect=new RectF(x,0,x+60.8f,60.8f);c.save();Path circle=new Path();circle.addOval(rect,Path.Direction.CW);c.clipPath(circle);p.setColor(showLogos?Color.WHITE:base);c.drawRect(rect,p);
  String value=team.optString("logo",home?"preset:bat":"");if(value.isEmpty()&&home)value="preset:bat";Bitmap image=showLogos?broadcastCrest(value):null;
  if(image!=null){p.setFilterBitmap(true);c.drawBitmap(image,null,rect,p);}else {String initials=team.optString("name").toUpperCase(Locale.ROOT);initials=initials.substring(0,Math.min(3,initials.length()));int ink=showLogos||(.299*Color.red(base)+.587*Color.green(base)+.114*Color.blue(base)>153)?Color.BLACK:Color.WHITE;broadcastText(c,p,initials,x+5,5,50.8f,50.8f,26,Paint.Align.CENTER,0,ink);}
  c.restore();p.setColor(Color.argb(128,255,255,255));p.setStyle(Paint.Style.STROKE);p.setStrokeWidth(1);c.drawOval(new RectF(x+.5f,.5f,x+60.3f,60.3f),p);p.setStyle(Paint.Style.FILL);
 }

 private int teamColor(String hex,int fallback){try{return hex.matches("#[0-9a-fA-F]{6}")?Color.parseColor(hex):fallback;}catch(Exception ignored){return fallback;}}
}
