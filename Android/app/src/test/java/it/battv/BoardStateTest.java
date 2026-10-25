package it.battv;
import static org.junit.Assert.*;
import org.json.*;
import org.junit.Test;

public class BoardStateTest {
 private JSONObject state()throws Exception{return new GameStore().state;}
 private String reading(long at,String key,int value)throws Exception{return new JSONObject().put("at",at).put("values",new JSONObject().put(key,value)).toString();}
 private String enable(String key,int value)throws Exception{return new JSONObject().put("field",key).put("value",value).toString();}
 @Test public void manualWinsAndOldPacketsCannotReEnable()throws Exception{
  JSONObject s=state();assertTrue(BoardState.apply(s,"boardReading",reading(1000,"homeScore",42),1000));assertEquals(0,s.getJSONObject("home").getInt("score"));
  assertTrue(BoardState.apply(s,"boardAuto",enable("homeScore",42),1001));assertEquals(42,s.getJSONObject("home").getInt("score"));
  assertTrue(BoardState.apply(s,"boardReading",reading(2000,"homeScore",44),2000));assertEquals(44,s.getJSONObject("home").getInt("score"));
  BoardState.override(s,"score","home");s.getJSONObject("home").put("score",45);
  assertTrue(BoardState.apply(s,"boardReading",reading(3000,"homeScore",44),3000));assertEquals(45,s.getJSONObject("home").getInt("score"));
  assertFalse(BoardState.apply(s,"boardReading",reading(2000,"homeScore",44),3000));
  assertFalse(BoardState.apply(s,"boardAuto",enable("homeScore",44),7000));assertFalse(BoardState.enabled(BoardState.get(s),"homeScore"));
 }
 @Test public void staleClockFreezesAndRequiresResume()throws Exception{
  JSONObject s=state();BoardState.apply(s,"boardReading",reading(1000,"clock",60),1000);BoardState.apply(s,"boardAuto",enable("clock",60),1000);
  BoardState.apply(s,"boardReading",reading(2000,"clock",59),2000);assertFalse(s.getBoolean("running"));assertEquals(59,GameStore.remaining(s,6000));
  BoardState.expire(s,6000);assertFalse(BoardState.enabled(BoardState.get(s),"clock"));BoardState.apply(s,"boardReading",reading(6001,"clock",55),6001);assertEquals(59,s.getInt("clock"));
 }
 @Test public void malformedJumpAndOtherFields()throws Exception{
  JSONObject s=state();assertFalse(BoardState.apply(s,"boardReading","{\"at\":1000,\"values\":{\"homeScore\":1.5}}",1000));
  assertFalse(BoardState.apply(s,"boardReading",reading(1000,"unknown",5),1000));assertFalse(BoardState.apply(s,"boardReading",reading(10000,"quarter",1),1000));
  BoardState.apply(s,"boardReading",reading(1000,"homeScore",42),1000);BoardState.apply(s,"boardAuto",enable("homeScore",42),1000);
  BoardState.apply(s,"boardReading",reading(2000,"homeScore",88),2000);assertEquals(42,s.getJSONObject("home").getInt("score"));assertFalse(BoardState.enabled(BoardState.get(s),"homeScore"));
  BoardState.apply(s,"boardReading",reading(2100,"quarter",2),2100);BoardState.apply(s,"boardAuto",enable("quarter",2),2100);s.getJSONObject("home").put("fouls",4);
  BoardState.apply(s,"boardReading",reading(2200,"quarter",3),2200);assertEquals(4,s.getJSONObject("home").getInt("fouls"));
 }
 @Test public void parserAndConsensus(){
  assertEquals(Integer.valueOf(624),BoardReadingFilter.parse("clock","10:24"));assertEquals(Integer.valueOf(10),BoardReadingFilter.parse("clock","9.8"));
  assertNull(BoardReadingFilter.parse("clock","1024"));assertNull(BoardReadingFilter.parse("homeScore","4O"));assertNull(BoardReadingFilter.parse("clock","10:78"));
  BoardReadingFilter f=new BoardReadingFilter();assertNull(f.observe("homeScore","42"));assertNull(f.observe("homeScore","42"));assertEquals(Integer.valueOf(42),f.observe("homeScore","42"));assertNull(f.observe("homeScore",""));assertNull(f.observe("homeScore","42"));
 }
}
