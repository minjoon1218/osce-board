/* 조별 고정 색상 — index.html(예약판)과 view.html(현황판)이 같이 씀
   조 이름을 정렬한 순서대로, 조 수만큼 색상환을 나눠 서로 다른 색을 하나씩 배정해요.
   - 이름순으로 이웃한 조(8A·8B 등)는 색상환에서 멀리 떨어진 색을 받도록 섞어서 배정
   - 짝수/홀수 번째 조는 밝기를 다르게 해서 비슷한 색끼리도 한 번 더 구분 */
(function(){
  /* '조 색상' 범례 표시 여부 — 다시 보이게 하려면 true */
  var SHOW_LEGEND=false;

  var st=document.createElement("style");document.head.appendChild(st);
  var teams=[],slots=0;

  function gcd(a,b){while(b){var t=b;b=a%b;a=t}return a}
  function build(n){
    n=Math.max(12,n);if(n===slots)return;slots=n;
    var step=Math.round(n*0.382);while(gcd(step,n)!==1)step++;
    var light="",dark="";
    for(var i=0;i<n;i++){
      var h=Math.round((i*step%n)*360/n),deep=i%2===1;
      light+="--tb"+i+":hsl("+h+" "+(deep?"72% 86%":"88% 93%")+");--ti"+i+":hsl("+h+" 72% "+(deep?"22%":"28%")+");--ts"+i+":hsl("+h+" "+(deep?"75% 38%":"78% 52%")+");";
      dark +="--tb"+i+":hsl("+h+" "+(deep?"40% 26%":"32% 19%")+");--ti"+i+":hsl("+h+" 80% "+(deep?"86%":"78%")+");--ts"+i+":hsl("+h+" "+(deep?"60% 68%":"70% 52%")+");";
    }
    st.textContent=":root{"+light+"}:root[data-theme=\"dark\"]{"+dark+"}";
  }
  function norm(t){return String(t==null?"":t).trim().toUpperCase()}
  function sortTeams(a){return a.slice().sort(function(x,y){return x.localeCompare(y,"ko",{numeric:true})})}
  build(12);

  window.OSCETeams={
    showLegend:SHOW_LEGEND,
    /* 조 목록 확정 (DB의 조 목록 + 예약에 나온 조) */
    set:function(list){var seen={},out=[];(list||[]).forEach(function(t){t=norm(t);if(t&&!seen[t]){seen[t]=1;out.push(t)}});teams=sortTeams(out);build(teams.length)},
    list:function(){return teams.slice()},
    index:function(t){t=norm(t);var i=teams.indexOf(t);if(i<0){var h=0;for(var k=0;k<t.length;k++)h=(h*31+t.charCodeAt(k))>>>0;i=h}return i%slots},
    style:function(t){var i=this.index(t);return "--pb:var(--tb"+i+");--pi:var(--ti"+i+");--ps:var(--ts"+i+")"}
  };
})();
