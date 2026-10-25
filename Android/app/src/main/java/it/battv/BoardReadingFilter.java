package it.battv;
import java.util.*;

/** Strict parser: do not guess O/0, missing colon, labels or partially lit digits. */
public final class BoardReadingFilter {
 private final Map<String,Integer> last=new HashMap<>(),counts=new HashMap<>();
 public static Integer parse(String field,String text){
  String s=text.replaceAll("\\s+","");int value;
  try{
   if(field.equals("clock")){
    if(s.matches("[0-9]{1,2}:[0-5][0-9]")){String[] p=s.split(":");value=Integer.parseInt(p[0])*60+Integer.parseInt(p[1]);}
    else if(s.matches("[0-5]?[0-9][.,][0-9]"))value=(int)Math.ceil(Double.parseDouble(s.replace(',','.')));
    else return null;
   }else{if(!s.matches("[0-9]{1,3}"))return null;value=Integer.parseInt(s);}
  }catch(Exception e){return null;}
  return BoardState.valid(field,value)?value:null;
 }
 public Integer observe(String key,String text){
  Integer v=parse(key,text);if(v==null){last.remove(key);counts.remove(key);return null;}
  int count=v.equals(last.get(key))?counts.getOrDefault(key,0)+1:1;last.put(key,v);counts.put(key,count);
  return count >= (key.equals("clock")?2:3)?v:null;
 }
 public void reset(){last.clear();counts.clear();}
}
