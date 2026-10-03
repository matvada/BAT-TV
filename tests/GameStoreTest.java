import it.battv.GameStore;
import org.json.JSONObject;
public class GameStoreTest {
 static JSONObject c(String id,String a,String team,int value)throws Exception{return new JSONObject().put("id",id).put("action",a).put("team",team).put("value",value);}
 static void check(boolean v,String m){if(!v)throw new AssertionError(m);}
 public static void main(String[]args)throws Exception{
  GameStore g=new GameStore();
  check(g.apply(c("one","score","home",2)),"score command rejected");
  check(g.state.getJSONObject("home").getInt("score")==2,"+2 failed");
  g.apply(c("one","score","home",2));check(g.state.getJSONObject("home").getInt("score")==2,"replayed command counted twice");
  g.apply(c("negative","score","away",-1));check(g.state.getJSONObject("away").getInt("score")==0,"negative score");
  check(!g.apply(c("invalid","score","unknown",2)),"unknown team accepted");
  g.apply(c("clock","clockSet",null,5));g.apply(c("start","clockStart",null,0));
  g.state.put("startedAt",System.currentTimeMillis()-2100);check(g.remaining()==3,"elapsed time incorrect");
  g.apply(c("stop","clockStop",null,0));check(g.remaining()==3&&!g.state.getBoolean("running"),"pause failed");
  g.apply(c("points","score","home",3));g.apply(c("undo","undo",null,0));check(g.state.getJSONObject("home").getInt("score")==2,"undo failed");
  check(!g.apply(c("badClock","clockSet",null,3601)),"unbounded clock accepted");
  JSONObject kiss=c("kiss","overlay",null,15).put("text","kiss");g.apply(kiss);check(g.state.getString("overlay").equals("kiss")&&g.state.getDouble("overlayUntil")>System.currentTimeMillis(),"timed overlay failed");
  check(g.envelope(true,false).getJSONObject("state").getJSONObject("home").getString("name").equals("BAT"),"wire envelope invalid");
  System.out.println("PASS: scores, replay protection, bounds, elapsed clock, pause, undo, timed overlay, wire envelope");
 }
}
