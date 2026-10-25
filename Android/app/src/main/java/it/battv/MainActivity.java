package it.battv;
import android.Manifest;
import android.app.*;
import android.content.*;
import android.content.pm.PackageManager;
import android.graphics.*;
import android.os.*;
import android.view.*;
import android.webkit.*;
import android.widget.*;
import com.pedro.common.ConnectChecker;
import com.pedro.library.rtmp.RtmpCamera2;
import com.pedro.library.view.OpenGlView;
import com.pedro.encoder.input.gl.render.filters.object.ImageObjectFilterRender;
import com.pedro.encoder.input.video.CameraHelper;
import org.json.*;
import java.util.*;

public final class MainActivity extends Activity implements BleLink.Events,ConnectChecker {
 private ValueCallback<android.net.Uri[]> logoUpload;
 private WebView web;private OpenGlView preview;private RtmpCamera2 camera;private ImageObjectFilterRender filter;private Bitmap logo,scoreWatermark;private Soundboard soundboard;
 private int videoHeight=1080;
 private int currentBitrate=1800000,stableReports=0;private boolean wantsLive=false;private int retryAttempts=0;
 private String lastOverlayKey="";
 private boolean readerRequested=false;
 private String boardSource="";
 private BoardReader reader;private long boardOffset=0,boardStateAt=0,boardSentAt=0;
 private BleLink link;private GameStore game;private String role="",pin="",serverUrl="",streamKey="";
 private boolean authenticated=false,ready=false,live=false;private int failedPins=0;private long lockUntil=0;
 private final Handler main=new Handler(Looper.getMainLooper());private final HashMap<String,Runnable> pending=new HashMap<>();
 @Override public void onCreate(Bundle b){super.onCreate(b);getWindow().addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON);getWindow().getDecorView().setSystemUiVisibility(View.SYSTEM_UI_FLAG_FULLSCREEN|View.SYSTEM_UI_FLAG_IMMERSIVE_STICKY|View.SYSTEM_UI_FLAG_HIDE_NAVIGATION);
  game=new GameStore();String saved=getPreferences(0).getString("game",null);if(getPreferences(0).getBoolean("matchInProgress",false)&&saved!=null)try{game.state=new JSONObject(saved);game.state.put("clock",game.remaining()).put("running",false).put("live",false).put("overlay","").put("overlayUntil",0);}catch(JSONException ignored){}
  try{game.state.remove("board");}catch(Exception ignored){}
  serverUrl=getPreferences(0).getString("server","");
  videoHeight=getPreferences(0).getInt("videoHeight",1080);if(videoHeight!=480&&videoHeight!=720&&videoHeight!=1080)videoHeight=1080;
  FrameLayout frame=new FrameLayout(this);preview=new OpenGlView(this);preview.setAspectRatioMode(com.pedro.encoder.utils.gl.AspectRatioMode.Adjust);frame.addView(preview,new FrameLayout.LayoutParams(-1,-1));
  web=new WebView(this);web.setBackgroundColor(Color.TRANSPARENT);web.getSettings().setJavaScriptEnabled(true);web.getSettings().setAllowFileAccess(true);web.getSettings().setAllowFileAccessFromFileURLs(false);web.getSettings().setAllowUniversalAccessFromFileURLs(false);
  web.setWebChromeClient(new WebChromeClient(){
   @Override public boolean onShowFileChooser(WebView view,ValueCallback<android.net.Uri[]> callback,FileChooserParams params){
    if(logoUpload!=null)logoUpload.onReceiveValue(null);logoUpload=callback;
    Intent intent=new Intent(Intent.ACTION_GET_CONTENT);intent.setType("image/*");intent.addCategory(Intent.CATEGORY_OPENABLE);
    try{startActivityForResult(Intent.createChooser(intent,"Scegli logo squadra"),2014);}catch(Exception e){logoUpload.onReceiveValue(null);logoUpload=null;status("Selezione immagini non disponibile");}return true;
   }
   @Override public boolean onJsPrompt(WebView view,String url,String message,String defaultValue,JsPromptResult result){
    EditText input=new EditText(MainActivity.this);input.setText(defaultValue);
    new AlertDialog.Builder(MainActivity.this).setTitle(message).setView(input).setPositiveButton("OK",(d,w)->result.confirm(input.getText().toString())).setNegativeButton("Annulla",(d,w)->result.cancel()).setOnCancelListener(d->result.cancel()).show();return true;
   }
  });
  web.setWebViewClient(new WebViewClient(){@Override public boolean shouldOverrideUrlLoading(WebView v,WebResourceRequest r){return true;}});
  web.addJavascriptInterface(new Bridge(),"Native");frame.addView(web,new FrameLayout.LayoutParams(-1,-1));setContentView(frame);web.loadUrl("file:///android_asset/index.html");
  showSplash(frame);
  logo=BitmapFactory.decodeResource(getResources(),R.drawable.bat_icon);
  try(java.io.InputStream input=getAssets().open("bat_watermark.jpg")){scoreWatermark=BitmapFactory.decodeStream(input);}catch(java.io.IOException e){android.util.Log.w("BAT tv","Filigrana non disponibile",e);}
  link=new BleLink(this,this);main.postDelayed(ticker,500);
 }
 private void showSplash(FrameLayout root){
  FrameLayout splash=new FrameLayout(this);splash.setBackgroundColor(Color.rgb(35,10,61));
  ImageView banner=new ImageView(this);banner.setScaleType(ImageView.ScaleType.CENTER_CROP);
  try(java.io.InputStream input=getAssets().open("launch_banner.jpg")){banner.setImageBitmap(BitmapFactory.decodeStream(input));}
  catch(java.io.IOException e){android.util.Log.w("BAT tv","Banner non disponibile",e);}
  int margin=(int)(10*getResources().getDisplayMetrics().density);
  splash.addView(banner,new FrameLayout.LayoutParams(-1,-1));
  String buildNumber="";
  try{buildNumber=String.valueOf(getPackageManager().getPackageInfo(getPackageName(),0).versionCode);}
  catch(PackageManager.NameNotFoundException ignored){}
  TextView build=new TextView(this);build.setText("BUILD "+buildNumber);
  build.setTextColor(Color.rgb(255,254,15));build.setTextSize(11);build.setLetterSpacing(0.14f);build.setGravity(Gravity.CENTER);
  build.setBackgroundColor(Color.argb(165,0,0,0));
  FrameLayout.LayoutParams label=new FrameLayout.LayoutParams(-1,-2,Gravity.BOTTOM|Gravity.CENTER_HORIZONTAL);
  label.bottomMargin=margin;splash.addView(build,label);
  root.addView(splash,new FrameLayout.LayoutParams(-1,-1));
  main.postDelayed(()->root.removeView(splash),2000);
 }
 private final Runnable ticker=new Runnable(){public void run(){
  try{if(role.equals("camera")){BoardState.expire(game.state,System.currentTimeMillis());if(game.state.optBoolean("running")&&game.remaining()==0)game.state.put("clock",0).put("running",false);JSONObject s=game.envelope(ready,live);emit(s);if(authenticated&&link.idle())link.send(s);if(ready)drawOverlay();}}
  catch(Exception e){status("Grafica: "+e.getMessage());}main.postDelayed(this,500);
 }};
 private void emit(JSONObject o){web.evaluateJavascript("window.receive("+o.toString()+")",null);}
 public void status(String s){try{emit(new JSONObject().put("type","status").put("message",s));}catch(JSONException ignored){}}
 public void found(String n,String a){try{emit(new JSONObject().put("type","device").put("name",n).put("address",a));}catch(JSONException ignored){}}
 public void message(JSONObject o){try{
  String type=o.optString("type");
  if(type.equals("unpaired")){authenticated=role.equals("camera")&&link.hasAuthorized();emit(o);return;}
  if(role.equals("camera")){
   if(type.equals("unpaired")){authenticated=false;return;}
   if(type.equals("pair")){
    if(System.currentTimeMillis()<lockUntil){link.send(new JSONObject().put("type","error").put("message","Attendi 30 secondi"));return;}
    if(!o.optString("pin").equals(pin)){if(++failedPins>=5){lockUntil=System.currentTimeMillis()+30000;failedPins=0;}link.send(new JSONObject().put("type","error").put("message","Codice errato"));return;}
    link.authorizeSender();authenticated=true;failedPins=0;status("Controller collegato via Bluetooth");link.send(game.envelope(ready,live));return;
   }
   if(!link.senderAuthorized()){link.send(new JSONObject().put("type","error").put("message","Inserisci il codice della Camera"));return;}
   if(type.equals("command"))apply(o,true);
  }else {
   if(type.equals("state")){boardOffset=o.optLong("serverNow")-System.currentTimeMillis();boardStateAt=SystemClock.elapsedRealtime();authenticated=true;emit(o);status("Collegato via Bluetooth");}
   else if(type.equals("ack")){Runnable timeout=pending.remove(o.optString("id"));if(timeout!=null)main.removeCallbacks(timeout);}
   else emit(o);
  }
 }catch(Exception e){status("Bluetooth: "+e.getMessage());}}
 private void apply(JSONObject o,boolean remote)throws JSONException{
  String a=o.optString("action");boolean accepted;
  if(a.equals("boardReading")&&remote){String sender=link.senderId();if(!boardSource.isEmpty()&&!boardSource.equals(sender)){if(System.currentTimeMillis()-BoardState.get(game.state).optDouble("lastAt")<=3000)return;game.state.remove("board");}boardSource=sender;}
  if(a.equals("liveStart")||a.equals("liveStop")){if(a.equals("liveStart"))beginLive();else endLive();accepted=true;}
  else if(a.equals("sound")){accepted=ready&&live&&soundboard!=null&&soundboard.play(o.optString("text"));if(!accepted)status("Avvia la diretta prima di usare i suoni");}
  else accepted=game.apply(o);
  if(!accepted){if(remote)link.send(new JSONObject().put("type","error").put("message","Comando non valido"));return;}
  if(!a.equals("boardReading"))getPreferences(0).edit().putString("game",game.state.toString()).apply();
  if(remote&&!a.equals("boardReading"))link.send(new JSONObject().put("type","ack").put("id",o.optString("id")));
  JSONObject state=game.envelope(ready,live);emit(state);if(authenticated&&link.idle())link.send(state);
 }
 private boolean permissions(boolean cameraMode){ArrayList<String> p=new ArrayList<>();
  if(Build.VERSION.SDK_INT>=31){p.add(Manifest.permission.BLUETOOTH_SCAN);p.add(Manifest.permission.BLUETOOTH_CONNECT);p.add(Manifest.permission.BLUETOOTH_ADVERTISE);}else p.add(Manifest.permission.ACCESS_FINE_LOCATION);
  if(cameraMode){p.add(Manifest.permission.CAMERA);p.add(Manifest.permission.RECORD_AUDIO);}
  ArrayList<String> missing=new ArrayList<>();for(String s:p)if(checkSelfPermission(s)!=PackageManager.PERMISSION_GRANTED)missing.add(s);
  if(!missing.isEmpty()){requestPermissions(missing.toArray(new String[0]),8);return false;}return true;
 }
 @Override public void onRequestPermissionsResult(int r,String[] p,int[] g){super.onRequestPermissionsResult(r,p,g);if(r==81){if(g.length>0&&g[0]==PackageManager.PERMISSION_GRANTED)startReader();else status("Consenti la fotocamera per leggere il tabellone");return;}boolean all=true;for(int n:g)if(n!=PackageManager.PERMISSION_GRANTED)all=false;if(all)activateRole();else status("Consenti i permessi per usare Bluetooth e Camera");}
 private void setRole(String selected){if(live||wantsLive){status("Ferma prima la diretta per cambiare ruolo");return;}if(!Arrays.asList("camera","regia","scores","").contains(selected))return;
  stopReader();stopCamera();link.close();authenticated=false;for(Runnable timeout:pending.values())main.removeCallbacks(timeout);pending.clear();role=selected;setRequestedOrientation(role.equals("scores")?android.content.pm.ActivityInfo.SCREEN_ORIENTATION_FULL_SENSOR:android.content.pm.ActivityInfo.SCREEN_ORIENTATION_LANDSCAPE);pin=String.format(Locale.US,"%06d",new java.security.SecureRandom().nextInt(1000000));
  if(role.equals("camera")){try{game.state.remove("board");boardSource="";game.state.put("overlay","").put("overlayUntil",0);getPreferences(0).edit().putString("game",game.state.toString()).apply();}catch(JSONException ignored){}}
  try{emit(new JSONObject().put("type","role").put("role",role).put("pin",pin));}catch(JSONException ignored){}
  if(!role.isEmpty()&&permissions(role.equals("camera")))activateRole();
 }
 private void activateRole(){if(role.equals("camera")){link.host();try{emit(game.envelope(ready,live));emit(new JSONObject().put("type","quality").put("height",videoHeight));}catch(JSONException ignored){}}else link.scan();}
 private void setQuality(int height){
  if(height!=480&&height!=720&&height!=1080)return;
  if(live||wantsLive||(camera!=null&&camera.isStreaming())){status("Ferma l’invio prima di cambiare risoluzione");return;}
  boolean restart=ready;if(restart)stopCamera();videoHeight=height;getPreferences(0).edit().putInt("videoHeight",height).apply();
  if(restart)startCamera();try{emit(new JSONObject().put("type","quality").put("height",videoHeight));}catch(JSONException ignored){}
 }
 private void focusCamera(double x,double y){
  if(!ready||camera==null)return;
  double scale=Math.min(preview.getWidth()/1280.0,preview.getHeight()/720.0);if(scale<=0)return;
  x=(x*preview.getWidth()-(preview.getWidth()-1280*scale)/2)/(1280*scale);
  y=(y*preview.getHeight()-(preview.getHeight()-720*scale)/2)/(720*scale);
  if(x<0||x>1||y<0||y>1)return;
  long now=android.os.SystemClock.uptimeMillis();
  MotionEvent event=MotionEvent.obtain(now,now,MotionEvent.ACTION_UP,(float)(x*preview.getWidth()),(float)(y*preview.getHeight()),0);
  try{if(!camera.tapToFocus(preview,event))status("Messa a fuoco non disponibile");}catch(Exception e){status("Messa a fuoco non disponibile");}finally{event.recycle();}
 }
 private void zoomCamera(double ratio){
  if(!ready||camera==null||!Double.isFinite(ratio))return;
  try{android.util.Range<Float> range=camera.getZoomRange();if(range!=null)camera.setZoom(Math.max(range.getLower(),Math.min(Math.min(6f,range.getUpper()),(float)(camera.getZoom()*ratio))));}
  catch(Exception e){status("Zoom non disponibile");}
 }
 private void startCamera(){if(ready)return;if(!permissions(true))return;
  int width=videoHeight==480?854:videoHeight==720?1280:1920;
  int bitRate=videoHeight==480?900000:videoHeight==720?1800000:3000000;
  try{camera=new RtmpCamera2(preview,this);if(!camera.prepareVideo(width,videoHeight,30,bitRate,0)||!camera.prepareAudio(96000,48000,false,false,false)){status("Camera o encoder "+videoHeight+"p non disponibile");camera=null;return;}
   currentBitrate=bitRate;stableReports=0;lastOverlayKey="";camera.getStreamClient().setLogs(false);camera.getStreamClient().setReTries(5);camera.getStreamClient().setCheckServerAlive(true);camera.getStreamClient().resizeCache(120);
   soundboard=new Soundboard(getAssets());camera.setCustomAudioEffect(soundboard);
   filter=new ImageObjectFilterRender();filter.setImage(Bitmap.createBitmap(width,videoHeight,Bitmap.Config.ARGB_8888));filter.setScale(100,100);filter.setPosition(0,0);
   camera.startPreview(CameraHelper.Facing.BACK,width,videoHeight,0);camera.getGlInterface().setFilter(filter);ready=true;drawOverlay();status("Camera "+videoHeight+"p pronta · tocca per il fuoco, pizzica per lo zoom");
  }catch(Exception e){stopCamera();status("Camera: "+e.getMessage());}}
 private void stopCamera(){endLive();if(soundboard!=null)soundboard.stop();if(camera!=null){camera.stopPreview();camera=null;}ready=false;filter=null;soundboard=null;}
 private void beginLive(){if(!role.equals("camera")||!ready||camera==null){status("Attiva prima la Camera");return;}if(live||camera.isStreaming())return;
  if(!serverUrl.startsWith("rtmps://")||streamKey.trim().isEmpty()){status("Imposta indirizzo RTMPS e chiave Facebook sulla Camera");return;}
  wantsLive=true;retryAttempts=0;camera.getStreamClient().setReTries(5);camera.startStream(serverUrl.replaceAll("/+$","")+"/"+streamKey.trim());status("Collegamento a Facebook…");}
 private void endLive(){wantsLive=false;boolean finished=live;if(soundboard!=null)soundboard.stop();if(camera!=null&&camera.isStreaming())camera.stopStream();live=false;if(finished){game=new GameStore();getPreferences(0).edit().putBoolean("matchInProgress",false).remove("game").apply();try{emit(game.envelope(ready,false));}catch(JSONException ignored){}}}
 private void abortLive(){wantsLive=false;if(camera!=null&&camera.isStreaming())camera.stopStream();live=false;}
 private void drawOverlay()throws JSONException{
  JSONObject visibleState=new JSONObject(game.state.toString());visibleState.remove("board");
  String renderKey=visibleState.toString()+"|"+game.remaining()+"|"+(game.state.optString("overlay").equals("glitter")?System.currentTimeMillis()/500:0)+"|"+(game.state.optDouble("overlayUntil")>0&&System.currentTimeMillis()>game.state.optDouble("overlayUntil"));if(renderKey.equals(lastOverlayKey))return;
  int width=videoHeight==480?854:videoHeight==720?1280:1920;Bitmap b=Bitmap.createBitmap(width,videoHeight,Bitmap.Config.ARGB_8888);Canvas c=new Canvas(b);c.scale(width/1280f,videoHeight/720f);Paint p=new Paint(Paint.ANTI_ALIAS_FLAG);p.setTypeface(Typeface.create(Typeface.DEFAULT,Typeface.BOLD));p.setColor(Color.WHITE);
  JSONObject s=game.state,h=s.getJSONObject("home"),a=s.getJSONObject("away");
  if(s.optBoolean("showScore"))drawBroadcastScore(c,p,s,h,a);
  String overlay=s.optString("overlay");if(s.optDouble("overlayUntil")>0&&System.currentTimeMillis()>s.optDouble("overlayUntil"))overlay="";
  if(broadcastRenderer==null)broadcastRenderer=new BroadcastRenderer(getAssets());
  broadcastRenderer.setViewport(preview.getWidth(),preview.getHeight());broadcastRenderer.drawCard(c,p,s,overlay,System.currentTimeMillis());
  p.setColor(Color.WHITE);p.setAlpha(255);p.setFilterBitmap(true);c.save();RectF visible=new RectF(0,0,1280,720);float channelWidth=visible.width()*.053f,channelX=visible.left+visible.width()*.917f,channelY=visible.top+visible.height()*.03f;RectF channel=new RectF(channelX,channelY,channelX+channelWidth,channelY+channelWidth);Path logoClip=new Path();logoClip.addRoundRect(channel,channelWidth*.18f,channelWidth*.18f,Path.Direction.CW);c.clipPath(logoClip);
  p.setColor(Color.argb(13,255,255,255));c.drawRect(channel,p);
  ColorMatrix gray=new ColorMatrix();gray.setSaturation(0);ColorMatrix light=new ColorMatrix(new float[]{.82f,0,0,0,63.75f,0,.82f,0,0,63.75f,0,0,.82f,0,63.75f,0,0,0,1,0});gray.postConcat(light);p.setColorFilter(new ColorMatrixColorFilter(gray));p.setAlpha(72);p.setXfermode(new PorterDuffXfermode(PorterDuff.Mode.SCREEN));c.drawBitmap(logo,new Rect(106,80,918,892),channel,p);p.setColorFilter(null);p.setXfermode(null);p.setAlpha(255);c.restore();p.setStyle(Paint.Style.STROKE);p.setColor(Color.argb(38,255,255,255));p.setStrokeWidth(.7f);c.drawRoundRect(channel,channelWidth*.18f,channelWidth*.18f,p);p.setStyle(Paint.Style.FILL);
  if(filter!=null){filter.setImage(b);lastOverlayKey=renderKey;}
 }
 private BroadcastRenderer broadcastRenderer;
 private Typeface broadcastFont;
 private void drawBroadcastScore(Canvas c,Paint p,JSONObject s,JSONObject h,JSONObject a){
  if(broadcastRenderer==null)broadcastRenderer=new BroadcastRenderer(getAssets());
  broadcastRenderer.setViewport(preview.getWidth(),preview.getHeight());
  broadcastRenderer.draw(c,p,s,h,a,game.remaining());
 }
 private void drawTriple(Canvas c,Paint p,long now){
  float pulse=1f+(float)Math.sin(now/170.0)*0.018f;c.save();c.scale(pulse,pulse,640,325);
  for(int i=0;i<14;i++){double angle=i*Math.PI*2/14+now/900.0;float inner=187,outer=i%2==0?234:218;
   p.setColor(i%2==0?Color.argb(230,255,254,15):Color.argb(140,255,254,15));p.setStrokeWidth(i%2==0?10:5);p.setStrokeCap(Paint.Cap.ROUND);
   c.drawLine(640+(float)Math.cos(angle)*inner,325+(float)Math.sin(angle)*inner,640+(float)Math.cos(angle)*outer,325+(float)Math.sin(angle)*outer,p);}
  p.setColor(Color.rgb(255,254,15));c.drawRoundRect(272,204,1008,446,16,16,p);
  p.setColor(Color.rgb(81,42,125));c.drawRoundRect(279,211,1001,439,14,14,p);
  p.setColor(Color.rgb(255,254,15));c.drawRoundRect(296,227,500,423,14,14,p);
  p.setTextAlign(Paint.Align.CENTER);label(c,p,"+3",398,379,137,Color.BLACK);
  label(c,p,"TRIPLA!",747,332,88,Color.WHITE);label(c,p,"BOMBA DA TRE",747,393,36,Color.rgb(255,254,15));
  p.setTextAlign(Paint.Align.LEFT);c.restore();
 }
 private void drawCheer(Canvas c,Paint p,long now,double until){
  double enter=Math.min(1,Math.max(0,(now-(until-8000))/650));
  double exit=Math.min(1,Math.max(0,(until-now)/500));
  float slide=(float)(-1150*(1-enter)+1150*(1-exit));
  c.save();c.translate(slide,0);p.setStyle(Paint.Style.FILL);
  p.setColor(Color.argb(240,81,42,125));c.drawRoundRect(105,232,1175,410,14,14,p);
  p.setColor(Color.rgb(255,254,15));c.drawRect(105,232,1175,240,p);c.drawRect(105,402,1175,410,p);
  c.save();c.clipRect(105,240,1175,402);p.setColor(Color.argb(107,255,254,15));
  float shift=(now%2400)/2400f*160;
  for(int x=-190;x<=1390;x+=160){float left=x+shift;Path slash=new Path();slash.moveTo(left,402);slash.lineTo(left+34,402);slash.lineTo(left+132,240);slash.lineTo(left+98,240);slash.close();c.drawPath(slash,p);}
  c.restore();p.setColor(Color.argb(245,81,42,125));c.drawRoundRect(337,247,943,395,14,14,p);
  p.setTextAlign(Paint.Align.CENTER);label(c,p,"FORZA BAT!",640,340,88,Color.rgb(255,254,15));
  label(c,p,"TUTTI INSIEME",640,380,26,Color.WHITE);p.setTextAlign(Paint.Align.LEFT);c.restore();
 }
 private void label(Canvas c,Paint p,String text,int x,int y,int size,int color){if(broadcastFont==null)broadcastFont=Typeface.createFromAsset(getAssets(),"broadcast/Galiga.ttf");p.setTypeface(broadcastFont);p.setTextSkewX(-.176327f);p.setTextSize(size);p.setColor(color);c.drawText(text,x,y,p);p.setTextSkewX(0);}
 private void scoreLabel(Canvas c,Paint p,String text,float x,float centerY,int size,int color){
  p.setTextSize(size);p.setColor(color);
  Rect bounds=new Rect();p.getTextBounds(text,0,text.length(),bounds);
  c.drawText(text,x,centerY-(bounds.top+bounds.bottom)/2f,p);
 }
 private void drawFouls(Canvas c,Paint p,int fouls,int x,int y){p.setStrokeWidth(1.5f);for(int i=0;i<5;i++){boolean active=i<fouls;p.setStyle(active?Paint.Style.FILL:Paint.Style.STROKE);p.setColor(active?(i==4?Color.RED:Color.rgb(255,254,15)):Color.argb(180,255,255,255));c.drawCircle(x+i*14,y,5,p);}p.setStyle(Paint.Style.FILL);}
 private int teamColor(String hex,int fallback){try{return hex.matches("#[0-9a-fA-F]{6}")?Color.parseColor(hex):fallback;}catch(Exception ignored){return fallback;}}
 public final class Bridge {
  @JavascriptInterface public void dispatch(String data){main.post(()->{try{JSONObject o=new JSONObject(data);String type=o.optString("type");
   switch(type){
    case "readerStart":startReader();break;
    case "readerStop":stopReader();break;
    case "readerRegions":if(role.equals("scores")&&reader!=null)reader.configure(o.optJSONObject("regions")!=null?o.optJSONObject("regions"):new JSONObject());break;
    case "role":setRole(o.optString("role"));break;
    case "scan":if(permissions(false))link.scan();break;
    case "connect":if(permissions(false))link.connect(o.getString("address"));break;
    case "pair":link.send(o);break;
    case "cameraStart":startCamera();break;
    case "cameraStop":stopCamera();break;
    case "cameraQuality":if(role.equals("camera"))setQuality(o.optInt("height"));break;
    case "cameraFocus":if(role.equals("camera"))focusCamera(o.optDouble("x"),o.optDouble("y"));break;
    case "cameraZoom":if(role.equals("camera"))zoomCamera(o.optDouble("ratio",1));break;
    case "destination":serverUrl=o.optString("url").trim();streamKey=o.optString("key").trim();getPreferences(0).edit().putString("server",serverUrl).apply();status("Destinazione salvata · chiave solo in memoria fino alla chiusura");break;
    case "command":if(role.equals("camera"))apply(o,false);else if(authenticated){String id=o.optString("id");Runnable timeout=()->{pending.remove(id);status("Comando non confermato · controlla la Camera prima di ripeterlo");};pending.put(id,timeout);main.postDelayed(timeout,5000);link.send(o);}else status("Collega e abbina prima la Camera");break;
   }
  }catch(Exception e){status("Operazione: "+e.getMessage());}});}
 }
 @Override public void onConnectionStarted(String url){main.post(()->status("Connessione video in corso…"));}
 @Override public void onConnectionSuccess(){main.post(()->{live=true;getPreferences(0).edit().putBoolean("matchInProgress",true).putString("game",game.state.toString()).apply();status("Invio video attivo · controlla Facebook Live Producer");});}
 @Override public void onConnectionFailed(String reason){main.post(()->{live=false;if(wantsLive&&camera!=null&&retryAttempts<5&&camera.getStreamClient().reTry(2000L<<retryAttempts,reason)){retryAttempts++;status("Riconnessione "+retryAttempts+"/5 · punteggi conservati");}else{abortLive();status("Invio interrotto: controlla rete e Facebook. Punteggi conservati.");}});}
 @Override public void onDisconnect(){main.post(()->{live=false;status("Invio video fermato");});}
 @Override public void onAuthError(){main.post(()->{abortLive();status("Chiave Facebook non accettata");});}
 @Override public void onAuthSuccess(){}
 @Override public void onNewBitrate(long bitrate){main.post(()->{
  if(!wantsLive||camera==null||!live)return;
  int ceiling=videoHeight==480?900000:videoHeight==720?1800000:3000000;
  int next=currentBitrate;
  if(camera.getStreamClient().hasCongestion()){stableReports=0;next=Math.max(400000,Math.min(currentBitrate*3/4,(int)Math.max(400000,bitrate*.65-96000)));}
  else if(++stableReports>=20){stableReports=0;next=Math.min(ceiling,currentBitrate+75000);}
  if(next!=currentBitrate){currentBitrate=next;camera.setVideoBitrateOnFly(next);}
  android.util.Log.i("BATStream","sentKbps="+bitrate/1000+" targetKbps="+currentBitrate/1000+" queued="+camera.getStreamClient().getItemsInCache()+" videoDropped="+camera.getStreamClient().getDroppedVideoFrames()+" audioDropped="+camera.getStreamClient().getDroppedAudioFrames());
 });}
 @Override protected void onActivityResult(int request,int result,Intent data){super.onActivityResult(request,result,data);if(request==2014&&logoUpload!=null){logoUpload.onReceiveValue(WebChromeClient.FileChooserParams.parseResult(result,data));logoUpload=null;}}
 @Override public void onBackPressed(){if(live){new AlertDialog.Builder(this).setMessage("Ferma l’invio video prima di cambiare ruolo.").setPositiveButton("OK",null).show();}else setRole("");}
 private void startReader(){
  if(!role.equals("scores"))return;
  if(checkSelfPermission(Manifest.permission.CAMERA)!=PackageManager.PERMISSION_GRANTED){requestPermissions(new String[]{Manifest.permission.CAMERA},81);return;}
  if(reader==null)reader=new BoardReader(this,new BoardReader.Events(){
   public void event(JSONObject o){emit(o);}
   public void reading(JSONObject values,long at){
    if(!role.equals("scores")||!authenticated||SystemClock.elapsedRealtime()-boardStateAt>4000||SystemClock.elapsedRealtime()-boardSentAt<700||!link.idle())return;
    boardSentAt=SystemClock.elapsedRealtime();
    try{JSONObject data=new JSONObject().put("at",at+boardOffset).put("values",values);
     link.send(new JSONObject().put("type","command").put("id",UUID.randomUUID().toString()).put("action","boardReading").put("text",data.toString()));
    }catch(JSONException ignored){}
   }
  });
  readerRequested=true;reader.start();try{emit(new JSONObject().put("type","readerStarted"));}catch(JSONException ignored){}
 }
 private void stopReader(){readerRequested=false;if(reader!=null)reader.stop();try{emit(new JSONObject().put("type","readerStopped"));}catch(JSONException ignored){}}
 @Override public void onConfigurationChanged(android.content.res.Configuration config){super.onConfigurationChanged(config);if(role.equals("scores")&&readerRequested){stopReader();try{emit(new JSONObject().put("type","readerRotated"));}catch(JSONException ignored){}startReader();}}
 @Override protected void onPause(){super.onPause();stopReader();}
 @Override protected void onDestroy(){if(reader!=null)reader.close();main.removeCallbacksAndMessages(null);stopCamera();link.close();web.destroy();super.onDestroy();}
}
