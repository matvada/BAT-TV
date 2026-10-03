package it.battv;
import android.Manifest;
import android.bluetooth.*;
import android.bluetooth.le.*;
import android.content.*;
import android.os.*;
import org.json.*;
import java.io.ByteArrayOutputStream;
import java.nio.charset.StandardCharsets;
import java.util.*;

@SuppressWarnings({"deprecation","MissingPermission"})
public final class BleLink {
 public static final UUID SERVICE=UUID.fromString("ba7a0001-9130-4d77-a6e0-ba7a20140001"),RX=UUID.fromString("ba7a0002-9130-4d77-a6e0-ba7a20140001"),TX=UUID.fromString("ba7a0003-9130-4d77-a6e0-ba7a20140001"),CCC=UUID.fromString("00002902-0000-1000-8000-00805f9b34fb");
 public interface Events {void status(String s);void found(String name,String address);void message(JSONObject o);}
 private final Context context;private final Events events;private final Handler main=new Handler(Looper.getMainLooper());
 private final BluetoothAdapter adapter;private BluetoothGatt client;private BluetoothGattServer server;private BluetoothDevice remote;
 private BluetoothGattCharacteristic rx,tx;private BluetoothLeAdvertiser advertiser;private BluetoothLeScanner scanner;
 private final ArrayDeque<byte[]> writes=new ArrayDeque<>(),notifies=new ArrayDeque<>();private final ByteArrayOutputStream input=new ByteArrayOutputStream();
 private boolean writing=false,notifying=false,scanning=false;private int mtu=23;
 private final HashSet<String> found=new HashSet<>();
 public BleLink(Context context,Events events){this.context=context;this.events=events;adapter=((BluetoothManager)context.getSystemService(Context.BLUETOOTH_SERVICE)).getAdapter();}
 public boolean enabled(){return adapter!=null&&adapter.isEnabled();}
 public void scan(){
  close();if(!enabled()){events.status("Attiva Bluetooth nelle Impostazioni");return;}
  scanner=adapter.getBluetoothLeScanner();if(scanner==null){events.status("Scansione Bluetooth non disponibile");return;}
  found.clear();scanning=true;events.status("Cerco BAT tv nelle vicinanze…");
  scanner.startScan(Collections.singletonList(new ScanFilter.Builder().setServiceUuid(new ParcelUuid(SERVICE)).build()),new ScanSettings.Builder().setScanMode(ScanSettings.SCAN_MODE_LOW_LATENCY).build(),scanCallback);
  main.postDelayed(()->{stopScan();events.status("Ricerca terminata · scegli il dispositivo o riprova");},15000);
 }
 private final ScanCallback scanCallback=new ScanCallback(){
  @Override public void onScanResult(int type,ScanResult result){main.post(()->{String a=result.getDevice().getAddress();if(found.add(a)){String n=result.getScanRecord()!=null?result.getScanRecord().getDeviceName():null;events.found(n!=null?n:"BAT tv Camera",a);}});}
  @Override public void onScanFailed(int code){main.post(()->events.status("Ricerca Bluetooth fallita: "+code));}
 };
 public void stopScan(){if(scanning&&scanner!=null){scanner.stopScan(scanCallback);scanning=false;}}
 public void connect(String address){stopScan();clearClient();events.status("Collegamento Bluetooth…");client=adapter.getRemoteDevice(address).connectGatt(context,false,clientCallback,BluetoothDevice.TRANSPORT_LE);}
 private void clearClient(){if(client!=null){client.disconnect();client.close();client=null;}writing=false;writes.clear();input.reset();mtu=23;}
 private final BluetoothGattCallback clientCallback=new BluetoothGattCallback(){
  @Override public void onConnectionStateChange(BluetoothGatt g,int status,int state){main.post(()->{if(g!=client)return;if(state==BluetoothProfile.STATE_CONNECTED){g.requestConnectionPriority(BluetoothGatt.CONNECTION_PRIORITY_HIGH);g.discoverServices();}else if(state==BluetoothProfile.STATE_DISCONNECTED){clearClient();events.status("Bluetooth scollegato · premi Cerca per ricollegarti");try{events.message(new JSONObject().put("type","unpaired"));}catch(JSONException ignored){}}});}
  @Override public void onServicesDiscovered(BluetoothGatt g,int status){main.post(()->{
   if(g!=client)return;BluetoothGattService s=g.getService(SERVICE);if(status!=0||s==null){events.status("Servizio BAT tv non disponibile");return;}
   rx=s.getCharacteristic(RX);tx=s.getCharacteristic(TX);if(rx==null||tx==null){events.status("Versione Bluetooth non compatibile");return;}
   if(!g.requestMtu(185))subscribe(g);
  });}
  @Override public void onMtuChanged(BluetoothGatt g,int m,int status){main.post(()->{if(g!=client)return;if(status==0)mtu=m;subscribe(g);});}
  @Override public void onDescriptorWrite(BluetoothGatt g,BluetoothGattDescriptor d,int status){main.post(()->{if(g!=client)return;events.status(status==0?"Bluetooth pronto · inserisci il codice della Camera":"Conferma l’abbinamento Bluetooth e riprova ("+status+")");});}
  @Override public void onCharacteristicWrite(BluetoothGatt g,BluetoothGattCharacteristic c,int status){main.post(()->{if(g!=client)return;writing=false;if(status!=0){writes.clear();events.status("Comando non inviato · ricollega Bluetooth ("+status+")");return;}if(!writes.isEmpty())writes.removeFirst();flushWrites();});}
  @Override public void onCharacteristicChanged(BluetoothGatt g,BluetoothGattCharacteristic c){byte[] v=c.getValue();if(v!=null)main.post(()->{if(g==client)receive(v);});}
  @Override public void onCharacteristicChanged(BluetoothGatt g,BluetoothGattCharacteristic c,byte[] value){main.post(()->{if(g==client)receive(value);});}
 };
 private void subscribe(BluetoothGatt g){if(tx==null)return;g.setCharacteristicNotification(tx,true);BluetoothGattDescriptor d=tx.getDescriptor(CCC);if(d==null){events.status("Notifiche BLE non disponibili");return;}d.setValue(BluetoothGattDescriptor.ENABLE_NOTIFICATION_VALUE);g.writeDescriptor(d);}
 public void host(){
  close();if(!enabled()){events.status("Attiva Bluetooth nelle Impostazioni");return;}
  advertiser=adapter.getBluetoothLeAdvertiser();if(advertiser==null){events.status("Questo Android non supporta Camera con Bluetooth periferico");return;}
  server=((BluetoothManager)context.getSystemService(Context.BLUETOOTH_SERVICE)).openGattServer(context,serverCallback);
  if(server==null){events.status("Impossibile aprire regia Bluetooth");return;}
  BluetoothGattService service=new BluetoothGattService(SERVICE,BluetoothGattService.SERVICE_TYPE_PRIMARY);
  rx=new BluetoothGattCharacteristic(RX,BluetoothGattCharacteristic.PROPERTY_WRITE,BluetoothGattCharacteristic.PERMISSION_WRITE_ENCRYPTED);
  tx=new BluetoothGattCharacteristic(TX,BluetoothGattCharacteristic.PROPERTY_NOTIFY,BluetoothGattCharacteristic.PERMISSION_READ_ENCRYPTED);
  BluetoothGattDescriptor descriptor=new BluetoothGattDescriptor(CCC,BluetoothGattDescriptor.PERMISSION_READ_ENCRYPTED|BluetoothGattDescriptor.PERMISSION_WRITE_ENCRYPTED);tx.addDescriptor(descriptor);
  service.addCharacteristic(rx);service.addCharacteristic(tx);server.addService(service);
 }
 private final AdvertiseCallback advertiseCallback=new AdvertiseCallback(){
  @Override public void onStartSuccess(AdvertiseSettings s){main.post(()->events.status("Camera visibile via Bluetooth · usa il codice sul tablet"));}
  @Override public void onStartFailure(int code){main.post(()->events.status("Pubblicazione Bluetooth fallita: "+code));}
 };
 private final BluetoothGattServerCallback serverCallback=new BluetoothGattServerCallback(){
  @Override public void onServiceAdded(int status,BluetoothGattService service){main.post(()->{
   if(server==null||advertiser==null)return;if(status!=0){events.status("Servizio BLE fallito: "+status);return;}
   advertiser.startAdvertising(new AdvertiseSettings.Builder().setAdvertiseMode(AdvertiseSettings.ADVERTISE_MODE_LOW_LATENCY).setConnectable(true).build(),new AdvertiseData.Builder().addServiceUuid(new ParcelUuid(SERVICE)).build(),advertiseCallback);
  });}
  @Override public void onConnectionStateChange(BluetoothDevice device,int status,int state){main.post(()->{if(state==BluetoothProfile.STATE_DISCONNECTED&&remote!=null&&remote.equals(device)){remote=null;input.reset();notifies.clear();notifying=false;events.status("Controller scollegato · la partita continua");try{events.message(new JSONObject().put("type","unpaired"));}catch(JSONException ignored){}}});}
  @Override public void onMtuChanged(BluetoothDevice device,int m){main.post(()->{if(remote==null||remote.equals(device))mtu=m;});}
  @Override public void onDescriptorWriteRequest(BluetoothDevice device,int id,BluetoothGattDescriptor descriptor,boolean prepared,boolean response,int offset,byte[] value){main.post(()->{
   if(server==null)return;boolean allowed=remote==null||remote.equals(device);
   if(prepared||offset!=0||!allowed){if(response)server.sendResponse(device,id,BluetoothGatt.GATT_FAILURE,offset,null);return;}
   if(response)server.sendResponse(device,id,BluetoothGatt.GATT_SUCCESS,0,null);
   if(Arrays.equals(value,BluetoothGattDescriptor.ENABLE_NOTIFICATION_VALUE)){remote=device;input.reset();notifies.clear();notifying=false;sendRaw("{\"type\":\"hello\",\"protocol\":1}");}
   else if(Arrays.equals(value,BluetoothGattDescriptor.DISABLE_NOTIFICATION_VALUE)){remote=null;notifies.clear();notifying=false;try{events.message(new JSONObject().put("type","unpaired"));}catch(JSONException ignored){}}
  });}
  @Override public void onCharacteristicWriteRequest(BluetoothDevice device,int id,BluetoothGattCharacteristic characteristic,boolean prepared,boolean response,int offset,byte[] value){main.post(()->{
   if(server==null)return;boolean allowed=remote!=null&&remote.equals(device)&&characteristic.getUuid().equals(RX)&&offset==0&&!prepared;
   if(response)server.sendResponse(device,id,allowed?BluetoothGatt.GATT_SUCCESS:BluetoothGatt.GATT_FAILURE,offset,null);
   if(allowed)receive(value);
  });}
  @Override public void onNotificationSent(BluetoothDevice device,int status){main.post(()->{notifying=false;if(status!=0){notifies.clear();events.status("Notifica Bluetooth non consegnata");return;}if(!notifies.isEmpty())notifies.removeFirst();flushNotifies();});}
 };
 private void receive(byte[] bytes){for(byte b:bytes){if(b==10){byte[] line=input.toByteArray();input.reset();try{events.message(new JSONObject(new String(line,StandardCharsets.UTF_8)));}catch(JSONException ignored){events.status("Messaggio Bluetooth non valido");}}else if(input.size()<8192)input.write(b);else {input.reset();events.status("Messaggio Bluetooth troppo grande");}}}
 public void send(JSONObject o){sendRaw(o.toString());}
 private void sendRaw(String json){byte[] data=(json+"\n").getBytes(StandardCharsets.UTF_8);int chunk=Math.max(20,Math.min(mtu-3,180));ArrayDeque<byte[]> q=server!=null?notifies:writes;if(q.size()>500){events.status("Bluetooth occupato · attendi");return;}for(int i=0;i<data.length;i+=chunk)q.add(Arrays.copyOfRange(data,i,Math.min(i+chunk,data.length)));if(server!=null)flushNotifies();else flushWrites();}
 private void flushWrites(){if(writing||writes.isEmpty()||client==null||rx==null)return;rx.setWriteType(BluetoothGattCharacteristic.WRITE_TYPE_DEFAULT);rx.setValue(writes.peekFirst());writing=client.writeCharacteristic(rx);if(!writing){writes.clear();events.status("Invio Bluetooth non riuscito");}}
 private void flushNotifies(){if(notifying||notifies.isEmpty()||server==null||remote==null||tx==null)return;tx.setValue(notifies.peekFirst());notifying=server.notifyCharacteristicChanged(remote,tx,false);if(!notifying){notifies.clear();events.status("Bluetooth non pronto");}}
 public boolean idle(){return writes.isEmpty()&&notifies.isEmpty();}
 public void close(){stopScan();clearClient();if(advertiser!=null){advertiser.stopAdvertising(advertiseCallback);advertiser=null;}if(server!=null){server.close();server=null;}remote=null;rx=null;tx=null;notifies.clear();notifying=false;}
}
