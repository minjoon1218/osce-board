/* 조별 고정 색상 — index.html(예약판)과 view.html(현황판)이 같이 씀
   조 이름을 정렬한 순서대로 서로 잘 구분되는 12가지 색을 하나씩 배정해요.
   (색이 비슷한 조가 이웃하지 않도록 순서를 섞어 배정) */
(function(){
  var HUES=[0,28,50,85,135,165,190,212,238,262,290,320];
  var ORDER=[0,6,3,9,1,7,4,10,2,8,5,11];
  var light="",dark="";
  for(var i=0;i<12;i++){var h=HUES[ORDER[i]];
    light+="--tb"+i+":hsl("+h+" 85% 92%);--ti"+i+":hsl("+h+" 70% 26%);--ts"+i+":hsl("+h+" 72% 47%);";
    dark +="--tb"+i+":hsl("+h+" 34% 21%);--ti"+i+":hsl("+h+" 80% 80%);--ts"+i+":hsl("+h+" 68% 58%);";}
  var st=document.createElement("style");
  st.textContent=":root{"+light+"}:root[data-theme=\"dark\"]{"+dark+"}";
  document.head.appendChild(st);

  var teams=[];
  function norm(t){return String(t==null?"":t).trim().toUpperCase()}
  function sortTeams(a){return a.slice().sort(function(x,y){return x.localeCompare(y,"ko",{numeric:true})})}
  window.OSCETeams={
    /* 조 목록 확정 (DB의 조 목록 + 예약에 나온 조) */
    set:function(list){var seen={},out=[];(list||[]).forEach(function(t){t=norm(t);if(t&&!seen[t]){seen[t]=1;out.push(t)}});teams=sortTeams(out)},
    list:function(){return teams.slice()},
    index:function(t){t=norm(t);var i=teams.indexOf(t);if(i<0){var h=0;for(var k=0;k<t.length;k++)h=(h*31+t.charCodeAt(k))>>>0;i=teams.length+h}return i%12},
    style:function(t){var i=this.index(t);return "--pb:var(--tb"+i+");--pi:var(--ti"+i+");--ps:var(--ts"+i+")"}
  };
})();
