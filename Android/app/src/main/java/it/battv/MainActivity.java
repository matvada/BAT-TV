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
 private WebView web;private OpenGlView preview;private RtmpCamera2 camera;private ImageObjectFilterRender filter;private Bitmap logo;
 private BleLink link;private GameStore game;private String role="",pin="",serverUrl="",streamKey="";
 private boolean authenticated=false,ready=false,live=false;private int failedPins=0;private long lockUntil=0;
 private final Handler main=new Handler(Looper.getMainLooper());private final HashMap<String,Runnable> pending=new HashMap<>();
 @Override public void onCreate(Bundle b){super.onCreate(b);getWindow().addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON);getWindow().getDecorView().setSystemUiVisibility(View.SYSTEM_UI_FLAG_FULLSCREEN|View.SYSTEM_UI_FLAG_IMMERSIVE_STICKY|View.SYSTEM_UI_FLAG_HIDE_NAVIGATION);
  game=new GameStore();String saved=getPreferences(0).getString("game",null);if(saved!=null)try{game.state=new JSONObject(saved);game.state.put("clock",game.remaining()).put("running",false).put("live",false).put("overlay","").put("overlayUntil",0);}catch(JSONException ignored){}
  serverUrl=getPreferences(0).getString("server","");
  FrameLayout frame=new FrameLayout(this);preview=new OpenGlView(this);frame.addView(preview,new FrameLayout.LayoutParams(-1,-1));
  web=new WebView(this);web.setBackgroundColor(Color.TRANSPARENT);web.getSettings().setJavaScriptEnabled(true);web.getSettings().setAllowFileAccess(true);web.getSettings().setAllowFileAccessFromFileURLs(false);web.getSettings().setAllowUniversalAccessFromFileURLs(false);
  web.setWebChromeClient(new WebChromeClient(){
   @Override public boolean onJsPrompt(WebView view,String url,String message,String defaultValue,JsPromptResult result){
    EditText input=new EditText(MainActivity.this);input.setText(defaultValue);
    new AlertDialog.Builder(MainActivity.this).setTitle(message).setView(input).setPositiveButton("OK",(d,w)->result.confirm(input.getText().toString())).setNegativeButton("Annulla",(d,w)->result.cancel()).setOnCancelListener(d->result.cancel()).show();return true;
   }
  });
  web.setWebViewClient(new WebViewClient(){@Override public boolean shouldOverrideUrlLoading(WebView v,WebResourceRequest r){return true;}});
  web.addJavascriptInterface(new Bridge(),"Native");frame.addView(web,new FrameLayout.LayoutParams(-1,-1));setContentView(frame);web.loadUrl("file:///android_asset/index.html");
  showSplash(frame);
  logo=BitmapFactory.decodeResource(getResources(),R.drawable.bat_icon);link=new BleLink(this,this);main.postDelayed(ticker,500);
 }
 private void showSplash(FrameLayout root){
  FrameLayout splash=new FrameLayout(this);splash.setBackgroundColor(Color.rgb(35,10,61));
  ImageView banner=new ImageView(this);banner.setScaleType(ImageView.ScaleType.FIT_CENTER);
  try(java.io.InputStream input=getAssets().open("logo.png")){banner.setImageBitmap(BitmapFactory.decodeStream(input));}
  catch(java.io.IOException e){android.util.Log.w("BAT tv","Banner non disponibile",e);}
  int margin=(int)(10*getResources().getDisplayMetrics().density);
  FrameLayout.LayoutParams art=new FrameLayout.LayoutParams(-1,-1);art.setMargins(margin,margin,margin,margin);
  splash.addView(banner,art);
  String buildNumber="";
  try{buildNumber=String.valueOf(getPackageManager().getPackageInfo(getPackageName(),0).versionCode);}
  catch(PackageManager.NameNotFoundException ignored){}
  TextView build=new TextView(this);build.setText("BUILD "+buildNumber);
  build.setTextColor(Color.rgb(255,254,15));build.setTextSize(11);build.setLetterSpacing(0.14f);build.setGravity(Gravity.CENTER);
  FrameLayout.LayoutParams label=new FrameLayout.LayoutParams(-1,-2,Gravity.BOTTOM|Gravity.CENTER_HORIZONTAL);
  label.bottomMargin=margin;splash.addView(build,label);
  root.addView(splash,new FrameLayout.LayoutParams(-1,-1));
  main.postDelayed(()->root.removeView(splash),2000);
 }
 private final Runnable ticker=new Runnable(){public void run(){
  try{if(role.equals("camera")){if(game.state.optBoolean("running")&&game.remaining()==0)game.state.put("clock",0).put("running",false);JSONObject s=game.envelope(ready,live);emit(s);if(authenticated&&link.idle())link.send(s);if(ready)drawOverlay();}}
  catch(Exception e){status("Grafica: "+e.getMessage());}main.postDelayed(this,500);
 }};
 private void emit(JSONObject o){web.evaluateJavascript("window.receive("+o.toString()+")",null);}
 public void status(String s){try{emit(new JSONObject().put("type","status").put("message",s));}catch(JSONException ignored){}}
 public void found(String n,String a){try{emit(new JSONObject().put("type","device").put("name",n).put("address",a));}catch(JSONException ignored){}}
 public void message(JSONObject o){try{
  String type=o.optString("type");
  if(type.equals("unpaired")){authenticated=false;emit(o);return;}
  if(role.equals("camera")){
   if(type.equals("unpaired")){authenticated=false;return;}
   if(type.equals("pair")){
    if(System.currentTimeMillis()<lockUntil){link.send(new JSONObject().put("type","error").put("message","Attendi 30 secondi"));return;}
    if(!o.optString("pin").equals(pin)){if(++failedPins>=5){lockUntil=System.currentTimeMillis()+30000;failedPins=0;}link.send(new JSONObject().put("type","error").put("message","Codice errato"));return;}
    authenticated=true;failedPins=0;status("Controller collegato via Bluetooth");link.send(game.envelope(ready,live));return;
   }
   if(!authenticated){link.send(new JSONObject().put("type","error").put("message","Inserisci il codice della Camera"));return;}
   if(type.equals("command"))apply(o,true);
  }else {
   if(type.equals("state")){authenticated=true;emit(o);status("Collegato via Bluetooth");}
   else if(type.equals("ack")){Runnable timeout=pending.remove(o.optString("id"));if(timeout!=null)main.removeCallbacks(timeout);}
   else emit(o);
  }
 }catch(Exception e){status("Bluetooth: "+e.getMessage());}}
 private void apply(JSONObject o,boolean remote)throws JSONException{
  String a=o.optString("action");boolean accepted;
  if(a.equals("liveStart")||a.equals("liveStop")){if(a.equals("liveStart"))beginLive();else endLive();accepted=true;}
  else accepted=game.apply(o);
  if(!accepted){if(remote)link.send(new JSONObject().put("type","error").put("message","Comando non valido"));return;}
  getPreferences(0).edit().putString("game",game.state.toString()).apply();
  if(remote)link.send(new JSONObject().put("type","ack").put("id",o.optString("id")));
  JSONObject state=game.envelope(ready,live);emit(state);if(authenticated)link.send(state);
 }
 private boolean permissions(boolean cameraMode){ArrayList<String> p=new ArrayList<>();
  if(Build.VERSION.SDK_INT>=31){p.add(Manifest.permission.BLUETOOTH_SCAN);p.add(Manifest.permission.BLUETOOTH_CONNECT);p.add(Manifest.permission.BLUETOOTH_ADVERTISE);}else p.add(Manifest.permission.ACCESS_FINE_LOCATION);
  if(cameraMode){p.add(Manifest.permission.CAMERA);p.add(Manifest.permission.RECORD_AUDIO);}
  ArrayList<String> missing=new ArrayList<>();for(String s:p)if(checkSelfPermission(s)!=PackageManager.PERMISSION_GRANTED)missing.add(s);
  if(!missing.isEmpty()){requestPermissions(missing.toArray(new String[0]),8);return false;}return true;
 }
 @Override public void onRequestPermissionsResult(int r,String[] p,int[] g){super.onRequestPermissionsResult(r,p,g);boolean all=true;for(int n:g)if(n!=PackageManager.PERMISSION_GRANTED)all=false;if(all)activateRole();else status("Consenti i permessi per usare Bluetooth e Camera");}
 private void setRole(String selected){if(live){status("Ferma prima la diretta per cambiare ruolo");return;}if(!Arrays.asList("camera","regia","scores","").contains(selected))return;
  stopCamera();link.close();authenticated=false;for(Runnable timeout:pending.values())main.removeCallbacks(timeout);pending.clear();role=selected;pin=String.format(Locale.US,"%06d",new java.security.SecureRandom().nextInt(1000000));
  if(role.equals("camera")){try{game.state.put("overlay","").put("overlayUntil",0);getPreferences(0).edit().putString("game",game.state.toString()).apply();}catch(JSONException ignored){}}
  try{emit(new JSONObject().put("type","role").put("role",role).put("pin",pin));}catch(JSONException ignored){}
  if(!role.isEmpty()&&permissions(role.equals("camera")))activateRole();
 }
 private void activateRole(){if(role.equals("camera")){link.host();try{emit(game.envelope(ready,live));}catch(JSONException ignored){}}else link.scan();}
 private void startCamera(){if(ready)return;if(!permissions(true))return;
  try{camera=new RtmpCamera2(preview,this);if(!camera.prepareVideo(1920,1080,30,5000000,0)||!camera.prepareAudio()){status("Camera o encoder 1080p non disponibile");camera=null;return;}
   filter=new ImageObjectFilterRender();filter.setImage(Bitmap.createBitmap(1920,1080,Bitmap.Config.ARGB_8888));filter.setScale(100,100);filter.setPosition(0,0);
   camera.startPreview(CameraHelper.Facing.BACK,1920,1080,0);camera.getGlInterface().setFilter(filter);ready=true;drawOverlay();status("Camera pronta · tieni aperta BAT tv");
  }catch(Exception e){stopCamera();status("Camera: "+e.getMessage());}}
 private void stopCamera(){endLive();if(camera!=null){camera.stopPreview();camera=null;}ready=false;filter=null;}
 private void beginLive(){if(!role.equals("camera")||!ready||camera==null){status("Attiva prima la Camera");return;}if(live||camera.isStreaming())return;
  if(!serverUrl.startsWith("rtmps://")||streamKey.trim().isEmpty()){status("Imposta indirizzo RTMPS e chiave Facebook sulla Camera");return;}
  camera.startStream(serverUrl.replaceAll("/+$","")+"/"+streamKey.trim());status("Collegamento a Facebook…");}
 private void endLive(){if(camera!=null&&camera.isStreaming())camera.stopStream();live=false;}
 private void drawOverlay()throws JSONException{
  Bitmap b=Bitmap.createBitmap(1920,1080,Bitmap.Config.ARGB_8888);Canvas c=new Canvas(b);c.scale(1.5f,1.5f);Paint p=new Paint(Paint.ANTI_ALIAS_FLAG);p.setTypeface(Typeface.create(Typeface.DEFAULT,Typeface.BOLD));p.setColor(Color.WHITE);
  JSONObject s=game.state,h=s.getJSONObject("home"),a=s.getJSONObject("away");
  if(s.optBoolean("showScore")){p.setColor(Color.argb(245,81,42,125));c.drawRoundRect(58,520,1222,604,14,14,p);label(c,p,h.optString("name"),86,571,24,Color.WHITE);label(c,p,""+h.optInt("score"),460,577,42,Color.WHITE);label(c,p,""+a.optInt("score"),760,577,42,Color.WHITE);label(c,p,a.optString("name"),925,571,24,Color.WHITE);
   String quarter=s.optInt("quarter")<=4?"Q"+s.optInt("quarter"):"OT"+(s.optInt("quarter")-4);
   if(s.optBoolean("clockEnabled",true)){int r=game.remaining();label(c,p,String.format(Locale.US,"%02d:%02d",r/60,r%60),565,563,32,Color.rgb(255,254,15));label(c,p,quarter,612,592,18,Color.LTGRAY);}
   else{p.setTextAlign(Paint.Align.CENTER);label(c,p,quarter,640,584,58,Color.rgb(255,254,15));p.setTextAlign(Paint.Align.LEFT);}}
  String overlay=s.optString("overlay");if(s.optDouble("overlayUntil")>0&&System.currentTimeMillis()>s.optDouble("overlayUntil"))overlay="";
  if(overlay.equals("kiss")){p.setColor(Color.rgb(81,42,125));p.setStyle(Paint.Style.STROKE);p.setStrokeWidth(28);c.drawRoundRect(30,80,1250,640,32,32,p);p.setColor(Color.rgb(255,254,15));p.setStrokeWidth(12);c.drawRoundRect(30,80,1250,640,32,32,p);p.setStyle(Paint.Style.FILL);p.setColor(Color.rgb(81,42,125));c.drawRoundRect(350,80,930,180,16,16,p);p.setTextAlign(Paint.Align.CENTER);label(c,p,"♥  KISS CAM  ♥",640,151,58,Color.WHITE);label(c,p,"♥",145,244,92,Color.rgb(255,254,15));label(c,p,"♥",1135,244,92,Color.rgb(255,254,15));p.setTextAlign(Paint.Align.LEFT);}
  else if(overlay.equals("triple"))drawTriple(c,p,System.currentTimeMillis());
  else if(overlay.equals("cheer"))drawCheer(c,p,System.currentTimeMillis(),s.optDouble("overlayUntil"));
  else if(overlay.equals("break")||overlay.equals("final")){p.setColor(Color.argb(230,81,42,125));c.drawRect(0,0,1280,720,p);p.setColor(Color.argb(85,0,0,0));c.drawRoundRect(170,205,1110,465,14,14,p);p.setColor(Color.rgb(255,254,15));c.drawRect(170,205,180,465,p);p.setTextAlign(Paint.Align.CENTER);label(c,p,overlay.equals("final")?"FINE PARTITA":"INTERVALLO",640,327,76,Color.WHITE);label(c,p,h.optString("name")+"  "+h.optInt("score")+" – "+a.optInt("score")+"  "+a.optString("name"),640,409,38,Color.rgb(255,254,15));p.setTextAlign(Paint.Align.LEFT);}
  else if(overlay.equals("caption")){p.setColor(Color.rgb(81,42,125));c.drawRoundRect(58,400,1222,490,14,14,p);p.setColor(Color.rgb(255,254,15));c.drawRect(58,400,67,490,p);label(c,p,s.optString("caption"),86,461,36,Color.WHITE);}
  p.setColor(Color.WHITE);c.drawBitmap(logo,null,new Rect(1162,82,1242,162),p);
  if(filter!=null)filter.setImage(b);
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
 private void label(Canvas c,Paint p,String text,int x,int y,int size,int color){p.setTextSize(size);p.setColor(color);c.drawText(text,x,y,p);}
 public final class Bridge {
  @JavascriptInterface public void dispatch(String data){main.post(()->{try{JSONObject o=new JSONObject(data);String type=o.optString("type");
   switch(type){
    case "role":setRole(o.optString("role"));break;
    case "scan":if(permissions(false))link.scan();break;
    case "connect":if(permissions(false))link.connect(o.getString("address"));break;
    case "pair":link.send(o);break;
    case "cameraStart":startCamera();break;
    case "cameraStop":stopCamera();break;
    case "destination":serverUrl=o.optString("url").trim();streamKey=o.optString("key").trim();getPreferences(0).edit().putString("server",serverUrl).apply();status("Destinazione salvata · chiave solo in memoria fino alla chiusura");break;
    case "command":if(role.equals("camera"))apply(o,false);else if(authenticated){String id=o.optString("id");Runnable timeout=()->{pending.remove(id);status("Comando non confermato · controlla la Camera prima di ripeterlo");};pending.put(id,timeout);main.postDelayed(timeout,5000);link.send(o);}else status("Collega e abbina prima la Camera");break;
   }
  }catch(Exception e){status("Operazione: "+e.getMessage());}});}
 }
 @Override public void onConnectionStarted(String url){main.post(()->status("Connessione video in corso…"));}
 @Override public void onConnectionSuccess(){main.post(()->{live=true;status("Invio video attivo · controlla Facebook Live Producer");});}
 @Override public void onConnectionFailed(String reason){main.post(()->{endLive();status("Invio video non riuscito: "+reason);});}
 @Override public void onDisconnect(){main.post(()->{live=false;status("Invio video fermato");});}
 @Override public void onAuthError(){main.post(()->{endLive();status("Chiave Facebook non accettata");});}
 @Override public void onAuthSuccess(){}
 @Override public void onBackPressed(){if(live){new AlertDialog.Builder(this).setMessage("Ferma l’invio video prima di cambiare ruolo.").setPositiveButton("OK",null).show();}else setRole("");}
 @Override protected void onDestroy(){main.removeCallbacksAndMessages(null);stopCamera();link.close();web.destroy();super.onDestroy();}
}
