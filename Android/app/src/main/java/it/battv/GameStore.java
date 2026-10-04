package it.battv;
import org.json.*;
import java.util.*;

/** Authoritative clock and state belong to the Camera, on either platform. */
public final class GameStore {
 public JSONObject state; public int revision=0;
 private final ArrayDeque<JSONObject> history=new ArrayDeque<>();
 private final LinkedHashSet<String> seen=new LinkedHashSet<>();
 public GameStore() { try {
  state=new JSONObject().put("home",team("BAT","#512A7D")).put("away",team("AVVERSARI","#FFFE0F"))
   .put("quarter",1).put("clock",600).put("clockEnabled",true).put("running",false).put("startedAt",System.currentTimeMillis())
   .put("overlay","").put("overlayUntil",0).put("caption","").put("showScore",true).put("live",false).put("liveCommand",0);
 }catch(JSONException e){throw new IllegalStateException(e);} }
 private JSONObject team(String n,String c)throws JSONException {return new JSONObject().put("name",n).put("color",c).put("logo","").put("score",0).put("fouls",0).put("timeouts",0);}
 public int remaining(){return remaining(state,System.currentTimeMillis());}
 public static int remaining(JSONObject s,long now){return Math.max(0,(int)Math.ceil(s.optDouble("clock")-(s.optBoolean("running")?(now-s.optDouble("startedAt"))/1000:0)));}
 public boolean apply(JSONObject c)throws JSONException {
  String id=c.optString("id"),a=c.optString("action");
  if(id.isEmpty()||id.length()>64)return false;
  if(seen.contains(id))return true;
  JSONObject next=new JSONObject(state.toString());int v=c.optInt("value");String t=c.optString("team"),text=c.optString("text");long now=System.currentTimeMillis();
  switch(a){
   case "score":case "foul":case "timeout":
    if(!t.equals("home")&&!t.equals("away")||v < -3||v>3)return false;
    String key=a.equals("score")?"score":a.equals("foul")?"fouls":"timeouts";
    JSONObject target=next.getJSONObject(t);target.put(key,Math.max(0,Math.min(a.equals("score")?999:99,target.optInt(key)+v)));break;
   case "clockStart":if(next.optBoolean("clockEnabled",true)&&!next.optBoolean("running")&&remaining()>0)next.put("running",true).put("startedAt",now);break;
   case "clockStop":next.put("clock",remaining()).put("running",false).put("startedAt",now);break;
   case "clockSet":if(v<0||v>3600)return false;next.put("clock",v).put("running",false).put("startedAt",now);break;
   case "clockEnabled":if(v!=0&&v!=1)return false;next.put("clock",remaining()).put("running",false).put("startedAt",now).put("clockEnabled",v==1);break;
   case "quarter":if(v<1||v>12)return false;next.put("quarter",v);break;
   case "overlay":if(!Arrays.asList("","kiss","triple","cheer","break","final","caption").contains(text))return false;
    next.put("overlay",text).put("overlayUntil",v>0?now+Math.min(v,300)*1000L:0);break;
   case "caption":next.put("caption",text.substring(0,Math.min(text.length(),100))).put("overlay","caption").put("overlayUntil",0);break;
   case "showScore":next.put("showScore",v!=0);break;
   case "rename":if(!t.equals("home")&&!t.equals("away")||text.trim().isEmpty())return false;
    next.getJSONObject(t).put("name",text.substring(0,Math.min(24,text.length())));break;
   case "undo":if(!history.isEmpty()){next=history.removeLast();next.put("clock",remaining(next,now)).put("running",false).put("live",state.optBoolean("live"));}break;
   default:return false;
  }
  if(!a.equals("undo")){history.add(new JSONObject(state.toString()));while(history.size()>30)history.removeFirst();}
  state=next;revision++;seen.add(id);while(seen.size()>100)seen.remove(seen.iterator().next());return true;
 }
 public JSONObject envelope(boolean ready,boolean live)throws JSONException {state.put("live",live);return new JSONObject().put("type","state").put("state",state).put("revision",revision).put("serverNow",System.currentTimeMillis()).put("cameraReady",ready).put("publishing",live);}
}
