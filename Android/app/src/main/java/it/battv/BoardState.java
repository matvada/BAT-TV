package it.battv;

import org.json.*;
import java.util.*;

/** Camera-side arbitration. OCR is a proposal, never a replacement for manual authority. */
public final class BoardState {
 public static final List<String> FIELDS=Arrays.asList("homeScore","awayScore","clock","quarter","homeFouls","awayFouls","homeTimeouts","awayTimeouts");
 public static int maximum(String key){return key.equals("clock")?3600:key.equals("quarter")?12:key.endsWith("Score")?999:9;}
 public static boolean valid(String k,int v){return FIELDS.contains(k)&&v>=(k.equals("quarter")?1:0)&&v<=maximum(k);}
 public static JSONObject get(JSONObject s)throws JSONException {
  JSONObject b=s.optJSONObject("board");if(b==null){b=new JSONObject().put("lastAt",0).put("automatic",new JSONArray()).put("candidates",new JSONObject());s.put("board",b);}return b;
 }
 public static boolean enabled(JSONObject b,String k){JSONArray a=b.optJSONArray("automatic");if(a!=null)for(int i=0;i<a.length();i++)if(k.equals(a.optString(i)))return true;return false;}
 public static void manual(JSONObject s,String field)throws JSONException {
  JSONObject b=get(s);JSONArray old=b.getJSONArray("automatic"),a=new JSONArray();
  for(int i=0;i<old.length();i++)if(!field.equals("all")&&!field.equals(old.optString(i)))a.put(old.optString(i));b.put("automatic",a);
 }
 public static void override(JSONObject s,String action,String team)throws JSONException {
  if(action.equals("undo")){manual(s,"all");return;}
  if(Arrays.asList("score","foul","timeout").contains(action))manual(s,team+(action.equals("score")?"Score":action.equals("foul")?"Fouls":"Timeouts"));
  if(action.startsWith("clock"))manual(s,"clock");
  if(action.equals("quarter")){manual(s,"quarter");manual(s,"homeFouls");manual(s,"awayFouls");}
 }
 public static boolean apply(JSONObject s,String action,String text,long now)throws JSONException {
  JSONObject b=get(s),c=b.getJSONObject("candidates");
  if(action.equals("boardManual")){if(!FIELDS.contains(text)&&!text.equals("all"))return false;manual(s,text);return true;}
  JSONObject p;try{if(text.length()>1600)return false;p=new JSONObject(text);}catch(Exception e){return false;}
  if(action.equals("boardAuto")){
   String k=p.optString("field");JSONObject candidate=c.optJSONObject(k);
   if(!FIELDS.contains(k)||candidate==null||now-candidate.optDouble("at")>3000||now<candidate.optDouble("at")||candidate.optInt("value",-1)!=p.optInt("value",-2))return false;
   if(!enabled(b,k))b.getJSONArray("automatic").put(k);set(s,k,candidate.getInt("value"),now);return true;
  }
  if(!action.equals("boardReading"))return false;
  double at=p.optDouble("at",0);JSONObject values=p.optJSONObject("values");
  if(!Double.isFinite(at)||at<=b.optDouble("lastAt",0)||at>now+500||now-at>3000||values==null)return false;
  for(Iterator<String> keys=values.keys();keys.hasNext();){String k=keys.next();Object v=values.get(k);if(!(v instanceof Number)||((Number)v).doubleValue()!=((Number)v).intValue()||!valid(k,((Number)v).intValue()))return false;}
  b.put("lastAt",at);
  for(Iterator<String> keys=values.keys();keys.hasNext();){
   String k=keys.next();int v=values.getInt(k);JSONObject prior=c.optJSONObject(k);
   c.put(k,new JSONObject().put("value",v).put("at",at));
   if(enabled(b,k)){
    // A gap or an implausible jump suspends this field until explicit operator review.
    boolean gap=prior==null||at-prior.optDouble("at")>3000;
    int delta=prior==null?0:v-prior.optInt("value");
    boolean jump=k.equals("clock")?(delta>0||delta < -5):k.endsWith("Score")?(delta<0||delta>3):k.equals("quarter")?Math.abs(delta)>1:Math.abs(delta)>1;
    if(gap||jump)manual(s,k);else set(s,k,v,now);
   }
  }
  return true;
 }
 private static void set(JSONObject s,String k,int v,long now)throws JSONException {
  if(k.equals("clock")){s.put("clock",v).put("running",false).put("startedAt",now);return;}
  if(k.equals("quarter")){s.put("quarter",v);return;}
  String team=k.startsWith("home")?"home":"away",part=k.substring(4);
  s.getJSONObject(team).put(part.equals("Score")?"score":part.equals("Fouls")?"fouls":"timeouts",v);
 }
 public static void expire(JSONObject s,long now)throws JSONException {
  JSONObject b=get(s),c=b.getJSONObject("candidates");for(String k:FIELDS){JSONObject v=c.optJSONObject(k);if(enabled(b,k)&&(v==null||now-v.optDouble("at")>3000))manual(s,k);}
 }
}
