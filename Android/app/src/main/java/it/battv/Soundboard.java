package it.battv;

import android.content.res.AssetManager;
import com.pedro.encoder.input.audio.CustomAudioEffect;
import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.util.HashMap;
import java.util.Map;

/** Mix short 32 kHz mono PCM cues into the microphone before AAC encoding. */
final class Soundboard extends CustomAudioEffect {
 private final Map<String,byte[]> cues=new HashMap<>();
 private byte[] current;
 private int offset;

 Soundboard(AssetManager assets) throws IOException {
  for(String name:new String[]{"horn","crowd","drums"}) {
   try(InputStream in=assets.open(name+".wav")) {
    ByteArrayOutputStream bytes=new ByteArrayOutputStream();
    byte[] buffer=new byte[8192];int n;
    while((n=in.read(buffer))!=-1)bytes.write(buffer,0,n);
    byte[] wav=bytes.toByteArray();
    if(wav.length<44)throw new IOException("Audio non valido: "+name);
    byte[] pcm=new byte[wav.length-44];
    System.arraycopy(wav,44,pcm,0,pcm.length);
    cues.put(name,pcm);
   }
  }
 }

 synchronized boolean play(String name) {
  byte[] cue=cues.get(name);
  if(cue==null)return false;
  current=cue;offset=0;
  return true;
 }

 synchronized void stop(){current=null;offset=0;}

 @Override public synchronized byte[] process(byte[] microphone) {
  byte[] cue=current;
  if(cue==null)return microphone;
  byte[] output=microphone.clone();
  int count=Math.min(output.length & ~1,cue.length-offset);
  for(int i=0;i<count;i+=2){
   int mic=(short)((output[i]&255)|(output[i+1]<<8));
   int effect=(short)((cue[offset+i]&255)|(cue[offset+i+1]<<8));
   int mixed=Math.max(-32768,Math.min(32767,Math.round(mic*.78f+effect*.62f)));
   output[i]=(byte)mixed;output[i+1]=(byte)(mixed>>8);
  }
  offset+=count;
  if(offset>=cue.length){current=null;offset=0;}
  return output;
 }
}
