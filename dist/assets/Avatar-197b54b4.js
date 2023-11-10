import{r as k,a as at,g as it,b as xe,O as Ye,j as Y,Q as Rt,_ as L,t as Ge,R as Qe,U as Et,d as st,s as Oe,V as At,u as lt,c as Ct}from"./index-43a5b071.js";import{c as Dt}from"./Menu-63248d8d.js";const jt={disableDefaultClasses:!1},kt=k.createContext(jt);function $t(e){const{disableDefaultClasses:t}=k.useContext(kt);return r=>t?"":e(r)}var S="top",H="bottom",N="right",M="left",$e="auto",ue=[S,H,N,M],te="start",ce="end",St="clippingParents",pt="viewport",se="popper",Mt="reference",Je=ue.reduce(function(e,t){return e.concat([t+"-"+te,t+"-"+ce])},[]),ct=[].concat(ue,[$e]).reduce(function(e,t){return e.concat([t,t+"-"+te,t+"-"+ce])},[]),Tt="beforeRead",Bt="read",Lt="afterRead",Wt="beforeMain",Ht="main",Nt="afterMain",Ft="beforeWrite",Vt="write",It="afterWrite",Ut=[Tt,Bt,Lt,Wt,Ht,Nt,Ft,Vt,It];function V(e){return e?(e.nodeName||"").toLowerCase():null}function B(e){if(e==null)return window;if(e.toString()!=="[object Window]"){var t=e.ownerDocument;return t&&t.defaultView||window}return e}function _(e){var t=B(e).Element;return e instanceof t||e instanceof Element}function W(e){var t=B(e).HTMLElement;return e instanceof t||e instanceof HTMLElement}function Se(e){if(typeof ShadowRoot>"u")return!1;var t=B(e).ShadowRoot;return e instanceof t||e instanceof ShadowRoot}function qt(e){var t=e.state;Object.keys(t.elements).forEach(function(r){var o=t.styles[r]||{},n=t.attributes[r]||{},a=t.elements[r];!W(a)||!V(a)||(Object.assign(a.style,o),Object.keys(n).forEach(function(p){var i=n[p];i===!1?a.removeAttribute(p):a.setAttribute(p,i===!0?"":i)}))})}function zt(e){var t=e.state,r={popper:{position:t.options.strategy,left:"0",top:"0",margin:"0"},arrow:{position:"absolute"},reference:{}};return Object.assign(t.elements.popper.style,r.popper),t.styles=r,t.elements.arrow&&Object.assign(t.elements.arrow.style,r.arrow),function(){Object.keys(t.elements).forEach(function(o){var n=t.elements[o],a=t.attributes[o]||{},p=Object.keys(t.styles.hasOwnProperty(o)?t.styles[o]:r[o]),i=p.reduce(function(s,c){return s[c]="",s},{});!W(n)||!V(n)||(Object.assign(n.style,i),Object.keys(a).forEach(function(s){n.removeAttribute(s)}))})}}const Xt={name:"applyStyles",enabled:!0,phase:"write",fn:qt,effect:zt,requires:["computeStyles"]};function F(e){return e.split("-")[0]}var Z=Math.max,we=Math.min,re=Math.round;function De(){var e=navigator.userAgentData;return e!=null&&e.brands&&Array.isArray(e.brands)?e.brands.map(function(t){return t.brand+"/"+t.version}).join(" "):navigator.userAgent}function ft(){return!/^((?!chrome|android).)*safari/i.test(De())}function oe(e,t,r){t===void 0&&(t=!1),r===void 0&&(r=!1);var o=e.getBoundingClientRect(),n=1,a=1;t&&W(e)&&(n=e.offsetWidth>0&&re(o.width)/e.offsetWidth||1,a=e.offsetHeight>0&&re(o.height)/e.offsetHeight||1);var p=_(e)?B(e):window,i=p.visualViewport,s=!ft()&&r,c=(o.left+(s&&i?i.offsetLeft:0))/n,l=(o.top+(s&&i?i.offsetTop:0))/a,d=o.width/n,w=o.height/a;return{width:d,height:w,top:l,right:c+d,bottom:l+w,left:c,x:c,y:l}}function Me(e){var t=oe(e),r=e.offsetWidth,o=e.offsetHeight;return Math.abs(t.width-r)<=1&&(r=t.width),Math.abs(t.height-o)<=1&&(o=t.height),{x:e.offsetLeft,y:e.offsetTop,width:r,height:o}}function ut(e,t){var r=t.getRootNode&&t.getRootNode();if(e.contains(t))return!0;if(r&&Se(r)){var o=t;do{if(o&&e.isSameNode(o))return!0;o=o.parentNode||o.host}while(o)}return!1}function q(e){return B(e).getComputedStyle(e)}function Yt(e){return["table","td","th"].indexOf(V(e))>=0}function G(e){return((_(e)?e.ownerDocument:e.document)||window.document).documentElement}function Pe(e){return V(e)==="html"?e:e.assignedSlot||e.parentNode||(Se(e)?e.host:null)||G(e)}function Ke(e){return!W(e)||q(e).position==="fixed"?null:e.offsetParent}function Gt(e){var t=/firefox/i.test(De()),r=/Trident/i.test(De());if(r&&W(e)){var o=q(e);if(o.position==="fixed")return null}var n=Pe(e);for(Se(n)&&(n=n.host);W(n)&&["html","body"].indexOf(V(n))<0;){var a=q(n);if(a.transform!=="none"||a.perspective!=="none"||a.contain==="paint"||["transform","perspective"].indexOf(a.willChange)!==-1||t&&a.willChange==="filter"||t&&a.filter&&a.filter!=="none")return n;n=n.parentNode}return null}function de(e){for(var t=B(e),r=Ke(e);r&&Yt(r)&&q(r).position==="static";)r=Ke(r);return r&&(V(r)==="html"||V(r)==="body"&&q(r).position==="static")?t:r||Gt(e)||t}function Te(e){return["top","bottom"].indexOf(e)>=0?"x":"y"}function le(e,t,r){return Z(e,we(t,r))}function Qt(e,t,r){var o=le(e,t,r);return o>r?r:o}function dt(){return{top:0,right:0,bottom:0,left:0}}function vt(e){return Object.assign({},dt(),e)}function mt(e,t){return t.reduce(function(r,o){return r[o]=e,r},{})}var Jt=function(t,r){return t=typeof t=="function"?t(Object.assign({},r.rects,{placement:r.placement})):t,vt(typeof t!="number"?t:mt(t,ue))};function Kt(e){var t,r=e.state,o=e.name,n=e.options,a=r.elements.arrow,p=r.modifiersData.popperOffsets,i=F(r.placement),s=Te(i),c=[M,N].indexOf(i)>=0,l=c?"height":"width";if(!(!a||!p)){var d=Jt(n.padding,r),w=Me(a),f=s==="y"?S:M,g=s==="y"?H:N,v=r.rects.reference[l]+r.rects.reference[s]-p[s]-r.rects.popper[l],m=p[s]-r.rects.reference[s],x=de(a),O=x?s==="y"?x.clientHeight||0:x.clientWidth||0:0,h=v/2-m/2,u=d[f],y=O-w[l]-d[g],b=O/2-w[l]/2+h,P=le(u,b,y),A=s;r.modifiersData[o]=(t={},t[A]=P,t.centerOffset=P-b,t)}}function Zt(e){var t=e.state,r=e.options,o=r.element,n=o===void 0?"[data-popper-arrow]":o;n!=null&&(typeof n=="string"&&(n=t.elements.popper.querySelector(n),!n)||ut(t.elements.popper,n)&&(t.elements.arrow=n))}const _t={name:"arrow",enabled:!0,phase:"main",fn:Kt,effect:Zt,requires:["popperOffsets"],requiresIfExists:["preventOverflow"]};function ne(e){return e.split("-")[1]}var er={top:"auto",right:"auto",bottom:"auto",left:"auto"};function tr(e,t){var r=e.x,o=e.y,n=t.devicePixelRatio||1;return{x:re(r*n)/n||0,y:re(o*n)/n||0}}function Ze(e){var t,r=e.popper,o=e.popperRect,n=e.placement,a=e.variation,p=e.offsets,i=e.position,s=e.gpuAcceleration,c=e.adaptive,l=e.roundOffsets,d=e.isFixed,w=p.x,f=w===void 0?0:w,g=p.y,v=g===void 0?0:g,m=typeof l=="function"?l({x:f,y:v}):{x:f,y:v};f=m.x,v=m.y;var x=p.hasOwnProperty("x"),O=p.hasOwnProperty("y"),h=M,u=S,y=window;if(c){var b=de(r),P="clientHeight",A="clientWidth";if(b===B(r)&&(b=G(r),q(b).position!=="static"&&i==="absolute"&&(P="scrollHeight",A="scrollWidth")),b=b,n===S||(n===M||n===N)&&a===ce){u=H;var E=d&&b===y&&y.visualViewport?y.visualViewport.height:b[P];v-=E-o.height,v*=s?1:-1}if(n===M||(n===S||n===H)&&a===ce){h=N;var R=d&&b===y&&y.visualViewport?y.visualViewport.width:b[A];f-=R-o.width,f*=s?1:-1}}var C=Object.assign({position:i},c&&er),T=l===!0?tr({x:f,y:v},B(r)):{x:f,y:v};if(f=T.x,v=T.y,s){var j;return Object.assign({},C,(j={},j[u]=O?"0":"",j[h]=x?"0":"",j.transform=(y.devicePixelRatio||1)<=1?"translate("+f+"px, "+v+"px)":"translate3d("+f+"px, "+v+"px, 0)",j))}return Object.assign({},C,(t={},t[u]=O?v+"px":"",t[h]=x?f+"px":"",t.transform="",t))}function rr(e){var t=e.state,r=e.options,o=r.gpuAcceleration,n=o===void 0?!0:o,a=r.adaptive,p=a===void 0?!0:a,i=r.roundOffsets,s=i===void 0?!0:i,c={placement:F(t.placement),variation:ne(t.placement),popper:t.elements.popper,popperRect:t.rects.popper,gpuAcceleration:n,isFixed:t.options.strategy==="fixed"};t.modifiersData.popperOffsets!=null&&(t.styles.popper=Object.assign({},t.styles.popper,Ze(Object.assign({},c,{offsets:t.modifiersData.popperOffsets,position:t.options.strategy,adaptive:p,roundOffsets:s})))),t.modifiersData.arrow!=null&&(t.styles.arrow=Object.assign({},t.styles.arrow,Ze(Object.assign({},c,{offsets:t.modifiersData.arrow,position:"absolute",adaptive:!1,roundOffsets:s})))),t.attributes.popper=Object.assign({},t.attributes.popper,{"data-popper-placement":t.placement})}const or={name:"computeStyles",enabled:!0,phase:"beforeWrite",fn:rr,data:{}};var ye={passive:!0};function nr(e){var t=e.state,r=e.instance,o=e.options,n=o.scroll,a=n===void 0?!0:n,p=o.resize,i=p===void 0?!0:p,s=B(t.elements.popper),c=[].concat(t.scrollParents.reference,t.scrollParents.popper);return a&&c.forEach(function(l){l.addEventListener("scroll",r.update,ye)}),i&&s.addEventListener("resize",r.update,ye),function(){a&&c.forEach(function(l){l.removeEventListener("scroll",r.update,ye)}),i&&s.removeEventListener("resize",r.update,ye)}}const ar={name:"eventListeners",enabled:!0,phase:"write",fn:function(){},effect:nr,data:{}};var ir={left:"right",right:"left",bottom:"top",top:"bottom"};function be(e){return e.replace(/left|right|bottom|top/g,function(t){return ir[t]})}var sr={start:"end",end:"start"};function _e(e){return e.replace(/start|end/g,function(t){return sr[t]})}function Be(e){var t=B(e),r=t.pageXOffset,o=t.pageYOffset;return{scrollLeft:r,scrollTop:o}}function Le(e){return oe(G(e)).left+Be(e).scrollLeft}function lr(e,t){var r=B(e),o=G(e),n=r.visualViewport,a=o.clientWidth,p=o.clientHeight,i=0,s=0;if(n){a=n.width,p=n.height;var c=ft();(c||!c&&t==="fixed")&&(i=n.offsetLeft,s=n.offsetTop)}return{width:a,height:p,x:i+Le(e),y:s}}function pr(e){var t,r=G(e),o=Be(e),n=(t=e.ownerDocument)==null?void 0:t.body,a=Z(r.scrollWidth,r.clientWidth,n?n.scrollWidth:0,n?n.clientWidth:0),p=Z(r.scrollHeight,r.clientHeight,n?n.scrollHeight:0,n?n.clientHeight:0),i=-o.scrollLeft+Le(e),s=-o.scrollTop;return q(n||r).direction==="rtl"&&(i+=Z(r.clientWidth,n?n.clientWidth:0)-a),{width:a,height:p,x:i,y:s}}function We(e){var t=q(e),r=t.overflow,o=t.overflowX,n=t.overflowY;return/auto|scroll|overlay|hidden/.test(r+n+o)}function ht(e){return["html","body","#document"].indexOf(V(e))>=0?e.ownerDocument.body:W(e)&&We(e)?e:ht(Pe(e))}function pe(e,t){var r;t===void 0&&(t=[]);var o=ht(e),n=o===((r=e.ownerDocument)==null?void 0:r.body),a=B(o),p=n?[a].concat(a.visualViewport||[],We(o)?o:[]):o,i=t.concat(p);return n?i:i.concat(pe(Pe(p)))}function je(e){return Object.assign({},e,{left:e.x,top:e.y,right:e.x+e.width,bottom:e.y+e.height})}function cr(e,t){var r=oe(e,!1,t==="fixed");return r.top=r.top+e.clientTop,r.left=r.left+e.clientLeft,r.bottom=r.top+e.clientHeight,r.right=r.left+e.clientWidth,r.width=e.clientWidth,r.height=e.clientHeight,r.x=r.left,r.y=r.top,r}function et(e,t,r){return t===pt?je(lr(e,r)):_(t)?cr(t,r):je(pr(G(e)))}function fr(e){var t=pe(Pe(e)),r=["absolute","fixed"].indexOf(q(e).position)>=0,o=r&&W(e)?de(e):e;return _(o)?t.filter(function(n){return _(n)&&ut(n,o)&&V(n)!=="body"}):[]}function ur(e,t,r,o){var n=t==="clippingParents"?fr(e):[].concat(t),a=[].concat(n,[r]),p=a[0],i=a.reduce(function(s,c){var l=et(e,c,o);return s.top=Z(l.top,s.top),s.right=we(l.right,s.right),s.bottom=we(l.bottom,s.bottom),s.left=Z(l.left,s.left),s},et(e,p,o));return i.width=i.right-i.left,i.height=i.bottom-i.top,i.x=i.left,i.y=i.top,i}function gt(e){var t=e.reference,r=e.element,o=e.placement,n=o?F(o):null,a=o?ne(o):null,p=t.x+t.width/2-r.width/2,i=t.y+t.height/2-r.height/2,s;switch(n){case S:s={x:p,y:t.y-r.height};break;case H:s={x:p,y:t.y+t.height};break;case N:s={x:t.x+t.width,y:i};break;case M:s={x:t.x-r.width,y:i};break;default:s={x:t.x,y:t.y}}var c=n?Te(n):null;if(c!=null){var l=c==="y"?"height":"width";switch(a){case te:s[c]=s[c]-(t[l]/2-r[l]/2);break;case ce:s[c]=s[c]+(t[l]/2-r[l]/2);break}}return s}function fe(e,t){t===void 0&&(t={});var r=t,o=r.placement,n=o===void 0?e.placement:o,a=r.strategy,p=a===void 0?e.strategy:a,i=r.boundary,s=i===void 0?St:i,c=r.rootBoundary,l=c===void 0?pt:c,d=r.elementContext,w=d===void 0?se:d,f=r.altBoundary,g=f===void 0?!1:f,v=r.padding,m=v===void 0?0:v,x=vt(typeof m!="number"?m:mt(m,ue)),O=w===se?Mt:se,h=e.rects.popper,u=e.elements[g?O:w],y=ur(_(u)?u:u.contextElement||G(e.elements.popper),s,l,p),b=oe(e.elements.reference),P=gt({reference:b,element:h,strategy:"absolute",placement:n}),A=je(Object.assign({},h,P)),E=w===se?A:b,R={top:y.top-E.top+x.top,bottom:E.bottom-y.bottom+x.bottom,left:y.left-E.left+x.left,right:E.right-y.right+x.right},C=e.modifiersData.offset;if(w===se&&C){var T=C[n];Object.keys(R).forEach(function(j){var I=[N,H].indexOf(j)>=0?1:-1,U=[S,H].indexOf(j)>=0?"y":"x";R[j]+=T[U]*I})}return R}function dr(e,t){t===void 0&&(t={});var r=t,o=r.placement,n=r.boundary,a=r.rootBoundary,p=r.padding,i=r.flipVariations,s=r.allowedAutoPlacements,c=s===void 0?ct:s,l=ne(o),d=l?i?Je:Je.filter(function(g){return ne(g)===l}):ue,w=d.filter(function(g){return c.indexOf(g)>=0});w.length===0&&(w=d);var f=w.reduce(function(g,v){return g[v]=fe(e,{placement:v,boundary:n,rootBoundary:a,padding:p})[F(v)],g},{});return Object.keys(f).sort(function(g,v){return f[g]-f[v]})}function vr(e){if(F(e)===$e)return[];var t=be(e);return[_e(e),t,_e(t)]}function mr(e){var t=e.state,r=e.options,o=e.name;if(!t.modifiersData[o]._skip){for(var n=r.mainAxis,a=n===void 0?!0:n,p=r.altAxis,i=p===void 0?!0:p,s=r.fallbackPlacements,c=r.padding,l=r.boundary,d=r.rootBoundary,w=r.altBoundary,f=r.flipVariations,g=f===void 0?!0:f,v=r.allowedAutoPlacements,m=t.options.placement,x=F(m),O=x===m,h=s||(O||!g?[be(m)]:vr(m)),u=[m].concat(h).reduce(function(ee,X){return ee.concat(F(X)===$e?dr(t,{placement:X,boundary:l,rootBoundary:d,padding:c,flipVariations:g,allowedAutoPlacements:v}):X)},[]),y=t.rects.reference,b=t.rects.popper,P=new Map,A=!0,E=u[0],R=0;R<u.length;R++){var C=u[R],T=F(C),j=ne(C)===te,I=[S,H].indexOf(T)>=0,U=I?"width":"height",D=fe(t,{placement:C,boundary:l,rootBoundary:d,altBoundary:w,padding:c}),$=I?j?N:M:j?H:S;y[U]>b[U]&&($=be($));var z=be($),Q=[];if(a&&Q.push(D[T]<=0),i&&Q.push(D[$]<=0,D[z]<=0),Q.every(function(ee){return ee})){E=C,A=!1;break}P.set(C,Q)}if(A)for(var ve=g?3:1,Re=function(X){var ie=u.find(function(he){var J=P.get(he);if(J)return J.slice(0,X).every(function(Ee){return Ee})});if(ie)return E=ie,"break"},ae=ve;ae>0;ae--){var me=Re(ae);if(me==="break")break}t.placement!==E&&(t.modifiersData[o]._skip=!0,t.placement=E,t.reset=!0)}}const hr={name:"flip",enabled:!0,phase:"main",fn:mr,requiresIfExists:["offset"],data:{_skip:!1}};function tt(e,t,r){return r===void 0&&(r={x:0,y:0}),{top:e.top-t.height-r.y,right:e.right-t.width+r.x,bottom:e.bottom-t.height+r.y,left:e.left-t.width-r.x}}function rt(e){return[S,N,H,M].some(function(t){return e[t]>=0})}function gr(e){var t=e.state,r=e.name,o=t.rects.reference,n=t.rects.popper,a=t.modifiersData.preventOverflow,p=fe(t,{elementContext:"reference"}),i=fe(t,{altBoundary:!0}),s=tt(p,o),c=tt(i,n,a),l=rt(s),d=rt(c);t.modifiersData[r]={referenceClippingOffsets:s,popperEscapeOffsets:c,isReferenceHidden:l,hasPopperEscaped:d},t.attributes.popper=Object.assign({},t.attributes.popper,{"data-popper-reference-hidden":l,"data-popper-escaped":d})}const yr={name:"hide",enabled:!0,phase:"main",requiresIfExists:["preventOverflow"],fn:gr};function br(e,t,r){var o=F(e),n=[M,S].indexOf(o)>=0?-1:1,a=typeof r=="function"?r(Object.assign({},t,{placement:e})):r,p=a[0],i=a[1];return p=p||0,i=(i||0)*n,[M,N].indexOf(o)>=0?{x:i,y:p}:{x:p,y:i}}function wr(e){var t=e.state,r=e.options,o=e.name,n=r.offset,a=n===void 0?[0,0]:n,p=ct.reduce(function(l,d){return l[d]=br(d,t.rects,a),l},{}),i=p[t.placement],s=i.x,c=i.y;t.modifiersData.popperOffsets!=null&&(t.modifiersData.popperOffsets.x+=s,t.modifiersData.popperOffsets.y+=c),t.modifiersData[o]=p}const xr={name:"offset",enabled:!0,phase:"main",requires:["popperOffsets"],fn:wr};function Or(e){var t=e.state,r=e.name;t.modifiersData[r]=gt({reference:t.rects.reference,element:t.rects.popper,strategy:"absolute",placement:t.placement})}const Pr={name:"popperOffsets",enabled:!0,phase:"read",fn:Or,data:{}};function Rr(e){return e==="x"?"y":"x"}function Er(e){var t=e.state,r=e.options,o=e.name,n=r.mainAxis,a=n===void 0?!0:n,p=r.altAxis,i=p===void 0?!1:p,s=r.boundary,c=r.rootBoundary,l=r.altBoundary,d=r.padding,w=r.tether,f=w===void 0?!0:w,g=r.tetherOffset,v=g===void 0?0:g,m=fe(t,{boundary:s,rootBoundary:c,padding:d,altBoundary:l}),x=F(t.placement),O=ne(t.placement),h=!O,u=Te(x),y=Rr(u),b=t.modifiersData.popperOffsets,P=t.rects.reference,A=t.rects.popper,E=typeof v=="function"?v(Object.assign({},t.rects,{placement:t.placement})):v,R=typeof E=="number"?{mainAxis:E,altAxis:E}:Object.assign({mainAxis:0,altAxis:0},E),C=t.modifiersData.offset?t.modifiersData.offset[t.placement]:null,T={x:0,y:0};if(b){if(a){var j,I=u==="y"?S:M,U=u==="y"?H:N,D=u==="y"?"height":"width",$=b[u],z=$+m[I],Q=$-m[U],ve=f?-A[D]/2:0,Re=O===te?P[D]:A[D],ae=O===te?-A[D]:-P[D],me=t.elements.arrow,ee=f&&me?Me(me):{width:0,height:0},X=t.modifiersData["arrow#persistent"]?t.modifiersData["arrow#persistent"].padding:dt(),ie=X[I],he=X[U],J=le(0,P[D],ee[D]),Ee=h?P[D]/2-ve-J-ie-R.mainAxis:Re-J-ie-R.mainAxis,yt=h?-P[D]/2+ve+J+he+R.mainAxis:ae+J+he+R.mainAxis,Ae=t.elements.arrow&&de(t.elements.arrow),bt=Ae?u==="y"?Ae.clientTop||0:Ae.clientLeft||0:0,He=(j=C==null?void 0:C[u])!=null?j:0,wt=$+Ee-He-bt,xt=$+yt-He,Ne=le(f?we(z,wt):z,$,f?Z(Q,xt):Q);b[u]=Ne,T[u]=Ne-$}if(i){var Fe,Ot=u==="x"?S:M,Pt=u==="x"?H:N,K=b[y],ge=y==="y"?"height":"width",Ve=K+m[Ot],Ie=K-m[Pt],Ce=[S,M].indexOf(x)!==-1,Ue=(Fe=C==null?void 0:C[y])!=null?Fe:0,qe=Ce?Ve:K-P[ge]-A[ge]-Ue+R.altAxis,ze=Ce?K+P[ge]+A[ge]-Ue-R.altAxis:Ie,Xe=f&&Ce?Qt(qe,K,ze):le(f?qe:Ve,K,f?ze:Ie);b[y]=Xe,T[y]=Xe-K}t.modifiersData[o]=T}}const Ar={name:"preventOverflow",enabled:!0,phase:"main",fn:Er,requiresIfExists:["offset"]};function Cr(e){return{scrollLeft:e.scrollLeft,scrollTop:e.scrollTop}}function Dr(e){return e===B(e)||!W(e)?Be(e):Cr(e)}function jr(e){var t=e.getBoundingClientRect(),r=re(t.width)/e.offsetWidth||1,o=re(t.height)/e.offsetHeight||1;return r!==1||o!==1}function kr(e,t,r){r===void 0&&(r=!1);var o=W(t),n=W(t)&&jr(t),a=G(t),p=oe(e,n,r),i={scrollLeft:0,scrollTop:0},s={x:0,y:0};return(o||!o&&!r)&&((V(t)!=="body"||We(a))&&(i=Dr(t)),W(t)?(s=oe(t,!0),s.x+=t.clientLeft,s.y+=t.clientTop):a&&(s.x=Le(a))),{x:p.left+i.scrollLeft-s.x,y:p.top+i.scrollTop-s.y,width:p.width,height:p.height}}function $r(e){var t=new Map,r=new Set,o=[];e.forEach(function(a){t.set(a.name,a)});function n(a){r.add(a.name);var p=[].concat(a.requires||[],a.requiresIfExists||[]);p.forEach(function(i){if(!r.has(i)){var s=t.get(i);s&&n(s)}}),o.push(a)}return e.forEach(function(a){r.has(a.name)||n(a)}),o}function Sr(e){var t=$r(e);return Ut.reduce(function(r,o){return r.concat(t.filter(function(n){return n.phase===o}))},[])}function Mr(e){var t;return function(){return t||(t=new Promise(function(r){Promise.resolve().then(function(){t=void 0,r(e())})})),t}}function Tr(e){var t=e.reduce(function(r,o){var n=r[o.name];return r[o.name]=n?Object.assign({},n,o,{options:Object.assign({},n.options,o.options),data:Object.assign({},n.data,o.data)}):o,r},{});return Object.keys(t).map(function(r){return t[r]})}var ot={placement:"bottom",modifiers:[],strategy:"absolute"};function nt(){for(var e=arguments.length,t=new Array(e),r=0;r<e;r++)t[r]=arguments[r];return!t.some(function(o){return!(o&&typeof o.getBoundingClientRect=="function")})}function Br(e){e===void 0&&(e={});var t=e,r=t.defaultModifiers,o=r===void 0?[]:r,n=t.defaultOptions,a=n===void 0?ot:n;return function(i,s,c){c===void 0&&(c=a);var l={placement:"bottom",orderedModifiers:[],options:Object.assign({},ot,a),modifiersData:{},elements:{reference:i,popper:s},attributes:{},styles:{}},d=[],w=!1,f={state:l,setOptions:function(x){var O=typeof x=="function"?x(l.options):x;v(),l.options=Object.assign({},a,l.options,O),l.scrollParents={reference:_(i)?pe(i):i.contextElement?pe(i.contextElement):[],popper:pe(s)};var h=Sr(Tr([].concat(o,l.options.modifiers)));return l.orderedModifiers=h.filter(function(u){return u.enabled}),g(),f.update()},forceUpdate:function(){if(!w){var x=l.elements,O=x.reference,h=x.popper;if(nt(O,h)){l.rects={reference:kr(O,de(h),l.options.strategy==="fixed"),popper:Me(h)},l.reset=!1,l.placement=l.options.placement,l.orderedModifiers.forEach(function(R){return l.modifiersData[R.name]=Object.assign({},R.data)});for(var u=0;u<l.orderedModifiers.length;u++){if(l.reset===!0){l.reset=!1,u=-1;continue}var y=l.orderedModifiers[u],b=y.fn,P=y.options,A=P===void 0?{}:P,E=y.name;typeof b=="function"&&(l=b({state:l,options:A,name:E,instance:f})||l)}}}},update:Mr(function(){return new Promise(function(m){f.forceUpdate(),m(l)})}),destroy:function(){v(),w=!0}};if(!nt(i,s))return f;f.setOptions(c).then(function(m){!w&&c.onFirstUpdate&&c.onFirstUpdate(m)});function g(){l.orderedModifiers.forEach(function(m){var x=m.name,O=m.options,h=O===void 0?{}:O,u=m.effect;if(typeof u=="function"){var y=u({state:l,name:x,instance:f,options:h}),b=function(){};d.push(y||b)}})}function v(){d.forEach(function(m){return m()}),d=[]}return f}}var Lr=[ar,Pr,or,Xt,xr,hr,Ar,_t,yr],Wr=Br({defaultModifiers:Lr});function Hr(e){return at("MuiPopper",e)}it("MuiPopper",["root"]);const Nr=["anchorEl","children","direction","disablePortal","modifiers","open","placement","popperOptions","popperRef","slotProps","slots","TransitionProps","ownerState"],Fr=["anchorEl","children","container","direction","disablePortal","keepMounted","modifiers","open","placement","popperOptions","popperRef","style","transition","slotProps","slots"];function Vr(e,t){if(t==="ltr")return e;switch(e){case"bottom-end":return"bottom-start";case"bottom-start":return"bottom-end";case"top-end":return"top-start";case"top-start":return"top-end";default:return e}}function ke(e){return typeof e=="function"?e():e}function Ir(e){return e.nodeType!==void 0}const Ur=()=>st({root:["root"]},$t(Hr)),qr={},zr=k.forwardRef(function(t,r){var o;const{anchorEl:n,children:a,direction:p,disablePortal:i,modifiers:s,open:c,placement:l,popperOptions:d,popperRef:w,slotProps:f={},slots:g={},TransitionProps:v}=t,m=xe(t,Nr),x=k.useRef(null),O=Ge(x,r),h=k.useRef(null),u=Ge(h,w),y=k.useRef(u);Qe(()=>{y.current=u},[u]),k.useImperativeHandle(w,()=>h.current,[]);const b=Vr(l,p),[P,A]=k.useState(b),[E,R]=k.useState(ke(n));k.useEffect(()=>{h.current&&h.current.forceUpdate()}),k.useEffect(()=>{n&&R(ke(n))},[n]),Qe(()=>{if(!E||!c)return;const U=z=>{A(z.placement)};let D=[{name:"preventOverflow",options:{altBoundary:i}},{name:"flip",options:{altBoundary:i}},{name:"onUpdate",enabled:!0,phase:"afterWrite",fn:({state:z})=>{U(z)}}];s!=null&&(D=D.concat(s)),d&&d.modifiers!=null&&(D=D.concat(d.modifiers));const $=Wr(E,x.current,L({placement:b},d,{modifiers:D}));return y.current($),()=>{$.destroy(),y.current(null)}},[E,i,s,c,d,b]);const C={placement:P};v!==null&&(C.TransitionProps=v);const T=Ur(),j=(o=g.root)!=null?o:"div",I=Et({elementType:j,externalSlotProps:f.root,externalForwardedProps:m,additionalProps:{role:"tooltip",ref:O},ownerState:t,className:T.root});return Y.jsx(j,L({},I,{children:typeof a=="function"?a(C):a}))}),Xr=k.forwardRef(function(t,r){const{anchorEl:o,children:n,container:a,direction:p="ltr",disablePortal:i=!1,keepMounted:s=!1,modifiers:c,open:l,placement:d="bottom",popperOptions:w=qr,popperRef:f,style:g,transition:v=!1,slotProps:m={},slots:x={}}=t,O=xe(t,Fr),[h,u]=k.useState(!0),y=()=>{u(!1)},b=()=>{u(!0)};if(!s&&!l&&(!v||h))return null;let P;if(a)P=a;else if(o){const R=ke(o);P=R&&Ir(R)?Ye(R).body:Ye(null).body}const A=!l&&s&&(!v||h)?"none":void 0,E=v?{in:l,onEnter:y,onExited:b}:void 0;return Y.jsx(Rt,{disablePortal:i,container:P,children:Y.jsx(zr,L({anchorEl:o,direction:p,disablePortal:i,modifiers:c,ref:r,open:v?!h:l,placement:d,popperOptions:w,popperRef:f,slotProps:m,slots:x},O,{style:L({position:"fixed",top:0,left:0,display:A},g),TransitionProps:E,children:n}))})}),Yr=["anchorEl","component","components","componentsProps","container","disablePortal","keepMounted","modifiers","open","placement","popperOptions","popperRef","transition","slots","slotProps"],Gr=Oe(Xr,{name:"MuiPopper",slot:"Root",overridesResolver:(e,t)=>t.root})({}),Qr=k.forwardRef(function(t,r){var o;const n=At(),a=lt({props:t,name:"MuiPopper"}),{anchorEl:p,component:i,components:s,componentsProps:c,container:l,disablePortal:d,keepMounted:w,modifiers:f,open:g,placement:v,popperOptions:m,popperRef:x,transition:O,slots:h,slotProps:u}=a,y=xe(a,Yr),b=(o=h==null?void 0:h.root)!=null?o:s==null?void 0:s.Root,P=L({anchorEl:p,container:l,disablePortal:d,keepMounted:w,modifiers:f,open:g,placement:v,popperOptions:m,popperRef:x,transition:O},y);return Y.jsx(Gr,L({as:i,direction:n==null?void 0:n.direction,slots:{root:b},slotProps:u??c},P,{ref:r}))}),so=Qr,Jr=Dt(Y.jsx("path",{d:"M12 12c2.21 0 4-1.79 4-4s-1.79-4-4-4-4 1.79-4 4 1.79 4 4 4zm0 2c-2.67 0-8 1.34-8 4v2h16v-2c0-2.66-5.33-4-8-4z"}),"Person");function Kr(e){return at("MuiAvatar",e)}it("MuiAvatar",["root","colorDefault","circular","rounded","square","img","fallback"]);const Zr=["alt","children","className","component","imgProps","sizes","src","srcSet","variant"],_r=e=>{const{classes:t,variant:r,colorDefault:o}=e;return st({root:["root",r,o&&"colorDefault"],img:["img"],fallback:["fallback"]},Kr,t)},eo=Oe("div",{name:"MuiAvatar",slot:"Root",overridesResolver:(e,t)=>{const{ownerState:r}=e;return[t.root,t[r.variant],r.colorDefault&&t.colorDefault]}})(({theme:e,ownerState:t})=>L({position:"relative",display:"flex",alignItems:"center",justifyContent:"center",flexShrink:0,width:40,height:40,fontFamily:e.typography.fontFamily,fontSize:e.typography.pxToRem(20),lineHeight:1,borderRadius:"50%",overflow:"hidden",userSelect:"none"},t.variant==="rounded"&&{borderRadius:(e.vars||e).shape.borderRadius},t.variant==="square"&&{borderRadius:0},t.colorDefault&&L({color:(e.vars||e).palette.background.default},e.vars?{backgroundColor:e.vars.palette.Avatar.defaultBg}:{backgroundColor:e.palette.mode==="light"?e.palette.grey[400]:e.palette.grey[600]}))),to=Oe("img",{name:"MuiAvatar",slot:"Img",overridesResolver:(e,t)=>t.img})({width:"100%",height:"100%",textAlign:"center",objectFit:"cover",color:"transparent",textIndent:1e4}),ro=Oe(Jr,{name:"MuiAvatar",slot:"Fallback",overridesResolver:(e,t)=>t.fallback})({width:"75%",height:"75%"});function oo({crossOrigin:e,referrerPolicy:t,src:r,srcSet:o}){const[n,a]=k.useState(!1);return k.useEffect(()=>{if(!r&&!o)return;a(!1);let p=!0;const i=new Image;return i.onload=()=>{p&&a("loaded")},i.onerror=()=>{p&&a("error")},i.crossOrigin=e,i.referrerPolicy=t,i.src=r,o&&(i.srcset=o),()=>{p=!1}},[e,t,r,o]),n}const no=k.forwardRef(function(t,r){const o=lt({props:t,name:"MuiAvatar"}),{alt:n,children:a,className:p,component:i="div",imgProps:s,sizes:c,src:l,srcSet:d,variant:w="circular"}=o,f=xe(o,Zr);let g=null;const v=oo(L({},s,{src:l,srcSet:d})),m=l||d,x=m&&v!=="error",O=L({},o,{colorDefault:!x,component:i,variant:w}),h=_r(O);return x?g=Y.jsx(to,L({alt:n,srcSet:d,src:l,sizes:c,ownerState:O,className:h.img},s)):a!=null?g=a:m&&n?g=n[0]:g=Y.jsx(ro,{ownerState:O,className:h.fallback}),Y.jsx(eo,L({as:i,ownerState:O,className:Ct(h.root,p),ref:r},f,{children:g}))}),lo=no;export{lo as A,so as P};
