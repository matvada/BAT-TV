package it.battv;
import static org.junit.Assert.*;
import android.bluetooth.*;
import org.json.*;
import org.junit.Test;
import org.junit.runner.RunWith;
import org.robolectric.RobolectricTestRunner;
import org.robolectric.RuntimeEnvironment;
import org.robolectric.annotation.Config;
import java.lang.reflect.*;
import java.nio.charset.StandardCharsets;
import java.util.*;

@RunWith(RobolectricTestRunner.class)
@Config(sdk=35)
public class BlePeersTest {
 @Test public void fragmentsAndAuthenticationStaySeparate()throws Exception{
  List<JSONObject> messages=new ArrayList<>();
  BleLink link=new BleLink(RuntimeEnvironment.getApplication(),new BleLink.Events(){public void status(String s){}public void found(String n,String a){}public void message(JSONObject o){messages.add(o);}});
  BluetoothAdapter adapter=BluetoothAdapter.getDefaultAdapter();
  Class<?> type=Class.forName("it.battv.BleLink$Peer");Constructor<?> constructor=type.getDeclaredConstructor(BluetoothDevice.class);constructor.setAccessible(true);
  Object regia=constructor.newInstance(adapter.getRemoteDevice("00:11:22:33:44:55")),scores=constructor.newInstance(adapter.getRemoteDevice("00:11:22:33:44:66"));
  Field active=BleLink.class.getDeclaredField("activePeer");active.setAccessible(true);
  Method receive=BleLink.class.getDeclaredMethod("receive",byte[].class);receive.setAccessible(true);
  active.set(link,regia);link.authorizeSender();assertTrue(link.senderAuthorized());receive.invoke(link,(Object)"{\"type\":\"command\",\"text\":\"reg".getBytes(StandardCharsets.UTF_8));
  active.set(link,scores);assertFalse(link.senderAuthorized());receive.invoke(link,(Object)"{\"type\":\"pair\",\"pin\":\"123456\"}\n".getBytes(StandardCharsets.UTF_8));assertEquals(1,messages.size());assertEquals("pair",messages.get(0).getString("type"));
  active.set(link,regia);assertTrue(link.senderAuthorized());receive.invoke(link,(Object)"ia\"}\n".getBytes(StandardCharsets.UTF_8));assertEquals(2,messages.size());assertEquals("regia",messages.get(1).getString("text"));
  link.close();
 }
}
