package it.battv;

import android.app.Activity;
import android.graphics.*;
import android.hardware.Camera;
import android.os.*;
import android.util.Base64;
import com.google.mlkit.vision.common.InputImage;
import com.google.mlkit.vision.text.*;
import com.google.mlkit.vision.text.latin.TextRecognizerOptions;
import com.google.android.gms.tasks.*;
import org.json.*;
import java.io.ByteArrayOutputStream;
import java.util.*;

/** Separate, silent capture on the scores device. Frames stay in its local WebView. */
@SuppressWarnings("deprecation")
public final class BoardReader {
 public interface Events {void event(JSONObject o);void reading(JSONObject values,long capturedAt);}
 private final Activity activity;private final Events events;private final Handler main=new Handler(Looper.getMainLooper());
 private final HandlerThread thread=new HandlerThread("BAT-board-reader");private final Handler worker;
 private Camera camera;private SurfaceTexture surface;private final TextRecognizer ocr=TextRecognition.getClient(TextRecognizerOptions.DEFAULT_OPTIONS);
 private volatile boolean stopped=true;private boolean busy=false;private long lastFrame;private int rotation;private volatile int generation;
 private final BoardReadingFilter filter=new BoardReadingFilter();private JSONObject regions=new JSONObject();
 public BoardReader(Activity a,Events e){activity=a;events=e;thread.start();worker=new Handler(thread.getLooper());}
 public void configure(JSONObject r){worker.post(()->{regions=r;filter.reset();generation++;});}
 private void emit(JSONObject o){main.post(()->{if(!stopped)events.event(o);});}
 private void error(String s){try{emit(new JSONObject().put("type","readerStatus").put("message",s));}catch(JSONException ignored){}}
 public void start(){worker.post(()->{
  if(!stopped)return;stopped=false;
  try{
   int id=-1;Camera.CameraInfo info=new Camera.CameraInfo();for(int i=0;i<Camera.getNumberOfCameras();i++){Camera.getCameraInfo(i,info);if(info.facing==Camera.CameraInfo.CAMERA_FACING_BACK){id=i;break;}}
   if(id<0)throw new IllegalStateException("Fotocamera posteriore non disponibile");
   int display=activity.getWindowManager().getDefaultDisplay().getRotation()*90;rotation=(info.orientation-display+360)%360;
   camera=Camera.open(id);Camera.Parameters p=camera.getParameters();
   Camera.Size size=Collections.min(p.getSupportedPreviewSizes(),Comparator.comparingInt(x->Math.abs(x.width*x.height-1280*720)));
   p.setPreviewSize(size.width,size.height);p.setPreviewFormat(ImageFormat.NV21);
   if(p.getSupportedFocusModes().contains(Camera.Parameters.FOCUS_MODE_CONTINUOUS_VIDEO))p.setFocusMode(Camera.Parameters.FOCUS_MODE_CONTINUOUS_VIDEO);
   camera.setParameters(p);surface=new SurfaceTexture(0);camera.setPreviewTexture(surface);
   camera.setPreviewCallback((data,c)->{
    long elapsed=SystemClock.elapsedRealtime();if(stopped||busy||elapsed-lastFrame<220)return;lastFrame=elapsed;busy=true;
    long capturedAt=System.currentTimeMillis();int epoch=generation;
    try{
     ByteArrayOutputStream bytes=new ByteArrayOutputStream();new YuvImage(data,ImageFormat.NV21,size.width,size.height,null).compressToJpeg(new Rect(0,0,size.width,size.height),85,bytes);
     byte[] jpeg=bytes.toByteArray();Bitmap raw=BitmapFactory.decodeByteArray(jpeg,0,jpeg.length);Matrix m=new Matrix();m.postRotate(rotation);
     Bitmap upright=Bitmap.createBitmap(raw,0,0,raw.getWidth(),raw.getHeight(),m,true);if(upright!=raw)raw.recycle();analyze(upright,capturedAt,epoch);
    }catch(Exception e){busy=false;error("Lettura non disponibile: "+e.getMessage());}
   });camera.startPreview();error("Inquadra il tabellone e disegna le zone delle cifre. Nessun audio acquisito.");
  }catch(Exception e){error("Fotocamera: "+e.getMessage());stop();}
 });}
 private void analyze(Bitmap image,long capturedAt,int epoch)throws JSONException {
  // Low-rate JPEG is only for calibration on this phone, never sent over BLE.
  ByteArrayOutputStream preview=new ByteArrayOutputStream();image.compress(Bitmap.CompressFormat.JPEG,55,preview);
  emit(new JSONObject().put("type","readerFrame").put("image","data:image/jpeg;base64,"+Base64.encodeToString(preview.toByteArray(),Base64.NO_WRAP)));
  List<Task<Text>> tasks=new ArrayList<>();List<String> keys=new ArrayList<>();List<Bitmap> crops=new ArrayList<>();
  for(String k:BoardState.FIELDS){JSONArray r=regions.optJSONArray(k);if(r==null||r.length()!=4)continue;
   double x=r.optDouble(0,-1),y=r.optDouble(1,-1),w=r.optDouble(2,0),h=r.optDouble(3,0);
   if(x<0||y<0||w<.01||h<.01||x+w>1.001||y+h>1.001)continue;
   int left=(int)(x*image.getWidth()),top=(int)(y*image.getHeight()),width=Math.min(image.getWidth()-left,(int)(w*image.getWidth())),height=Math.min(image.getHeight()-top,(int)(h*image.getHeight()));
   if(width<8||height<8)continue;
   Bitmap crop=Bitmap.createBitmap(image,left,top,width,height);crops.add(crop);keys.add(k);tasks.add(ocr.process(InputImage.fromBitmap(crop,0)));
  }
  Tasks.whenAllComplete(tasks).addOnCompleteListener(task->worker.post(()->{
   try{
    if(!stopped&&epoch==generation){JSONObject values=new JSONObject(),raw=new JSONObject();
     for(int i=0;i<tasks.size();i++){String text=tasks.get(i).isSuccessful()?tasks.get(i).getResult().getText():"";String k=keys.get(i);raw.put(k,text);Integer v=filter.observe(k,text);if(v!=null)values.put(k,v);}
     emit(new JSONObject().put("type","readerValues").put("values",values).put("raw",raw));
     main.post(()->{if(!stopped&&epoch==generation&&System.currentTimeMillis()-capturedAt<2000)events.reading(values,capturedAt);});
    }
   }catch(Exception e){error("Lettura incerta · controlla le zone selezionate");}
   finally{for(Bitmap b:crops)if(b!=image)b.recycle();image.recycle();busy=false;}
  }));
 }
 public void stop(){stopped=true;worker.post(()->{generation++;filter.reset();if(camera!=null){camera.setPreviewCallback(null);camera.stopPreview();camera.release();camera=null;}if(surface!=null){surface.release();surface=null;}});}
 public void close(){stop();worker.post(()->{ocr.close();thread.quitSafely();});}
}
