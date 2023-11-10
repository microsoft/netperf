import{r as n,ao as tt,a as Z,g as ee,s as q,q as te,u as re,b as K,_ as E,j as k,c as Q,d as se,an as ot,R as nt,ap as rt,O as oe,t as be,k as Ke,aq as st,ar as it,as as De,at as lt,z as at,au as Fe,U as ne,J as ct,av as ut,a3 as dt}from"./index-43a5b071.js";var p={};/**
 * @license React
 * react-is.production.min.js
 *
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */var xe=Symbol.for("react.element"),Ee=Symbol.for("react.portal"),ie=Symbol.for("react.fragment"),le=Symbol.for("react.strict_mode"),ae=Symbol.for("react.profiler"),ce=Symbol.for("react.provider"),ue=Symbol.for("react.context"),ft=Symbol.for("react.server_context"),de=Symbol.for("react.forward_ref"),fe=Symbol.for("react.suspense"),pe=Symbol.for("react.suspense_list"),me=Symbol.for("react.memo"),he=Symbol.for("react.lazy"),pt=Symbol.for("react.offscreen"),We;We=Symbol.for("react.module.reference");function N(e){if(typeof e=="object"&&e!==null){var t=e.$$typeof;switch(t){case xe:switch(e=e.type,e){case ie:case ae:case le:case fe:case pe:return e;default:switch(e=e&&e.$$typeof,e){case ft:case ue:case de:case he:case me:case ce:return e;default:return t}}case Ee:return t}}}p.ContextConsumer=ue;p.ContextProvider=ce;p.Element=xe;p.ForwardRef=de;p.Fragment=ie;p.Lazy=he;p.Memo=me;p.Portal=Ee;p.Profiler=ae;p.StrictMode=le;p.Suspense=fe;p.SuspenseList=pe;p.isAsyncMode=function(){return!1};p.isConcurrentMode=function(){return!1};p.isContextConsumer=function(e){return N(e)===ue};p.isContextProvider=function(e){return N(e)===ce};p.isElement=function(e){return typeof e=="object"&&e!==null&&e.$$typeof===xe};p.isForwardRef=function(e){return N(e)===de};p.isFragment=function(e){return N(e)===ie};p.isLazy=function(e){return N(e)===he};p.isMemo=function(e){return N(e)===me};p.isPortal=function(e){return N(e)===Ee};p.isProfiler=function(e){return N(e)===ae};p.isStrictMode=function(e){return N(e)===le};p.isSuspense=function(e){return N(e)===fe};p.isSuspenseList=function(e){return N(e)===pe};p.isValidElementType=function(e){return typeof e=="string"||typeof e=="function"||e===ie||e===ae||e===le||e===fe||e===pe||e===pt||typeof e=="object"&&e!==null&&(e.$$typeof===he||e.$$typeof===me||e.$$typeof===ce||e.$$typeof===ue||e.$$typeof===de||e.$$typeof===We||e.getModuleId!==void 0)};p.typeOf=N;let ke=0;function mt(e){const[t,o]=n.useState(e),i=e||t;return n.useEffect(()=>{t==null&&(ke+=1,o(`mui-${ke}`))},[t]),i}const Ne=tt["useId".toString()];function Qt(e){if(Ne!==void 0){const t=Ne();return e??t}return mt(e)}function Zt({controlled:e,default:t,name:o,state:i="value"}){const{current:r}=n.useRef(e!==void 0),[h,u]=n.useState(t),l=r?e:h,a=n.useCallback(g=>{r||u(g)},[]);return[l,a]}function ht(e){return Z("MuiSvgIcon",e)}ee("MuiSvgIcon",["root","colorPrimary","colorSecondary","colorAction","colorError","colorDisabled","fontSizeInherit","fontSizeSmall","fontSizeMedium","fontSizeLarge"]);const gt=["children","className","color","component","fontSize","htmlColor","inheritViewBox","titleAccess","viewBox"],yt=e=>{const{color:t,fontSize:o,classes:i}=e,r={root:["root",t!=="inherit"&&`color${te(t)}`,`fontSize${te(o)}`]};return se(r,ht,i)},vt=q("svg",{name:"MuiSvgIcon",slot:"Root",overridesResolver:(e,t)=>{const{ownerState:o}=e;return[t.root,o.color!=="inherit"&&t[`color${te(o.color)}`],t[`fontSize${te(o.fontSize)}`]]}})(({theme:e,ownerState:t})=>{var o,i,r,h,u,l,a,g,w,y,$,P,C;return{userSelect:"none",width:"1em",height:"1em",display:"inline-block",fill:t.hasSvgAsChild?void 0:"currentColor",flexShrink:0,transition:(o=e.transitions)==null||(i=o.create)==null?void 0:i.call(o,"fill",{duration:(r=e.transitions)==null||(r=r.duration)==null?void 0:r.shorter}),fontSize:{inherit:"inherit",small:((h=e.typography)==null||(u=h.pxToRem)==null?void 0:u.call(h,20))||"1.25rem",medium:((l=e.typography)==null||(a=l.pxToRem)==null?void 0:a.call(l,24))||"1.5rem",large:((g=e.typography)==null||(w=g.pxToRem)==null?void 0:w.call(g,35))||"2.1875rem"}[t.fontSize],color:(y=($=(e.vars||e).palette)==null||($=$[t.color])==null?void 0:$.main)!=null?y:{action:(P=(e.vars||e).palette)==null||(P=P.action)==null?void 0:P.active,disabled:(C=(e.vars||e).palette)==null||(C=C.action)==null?void 0:C.disabled,inherit:void 0}[t.color]}}),Ve=n.forwardRef(function(t,o){const i=re({props:t,name:"MuiSvgIcon"}),{children:r,className:h,color:u="inherit",component:l="svg",fontSize:a="medium",htmlColor:g,inheritViewBox:w=!1,titleAccess:y,viewBox:$="0 0 24 24"}=i,P=K(i,gt),C=n.isValidElement(r)&&r.type==="svg",M=E({},i,{color:u,component:l,fontSize:a,instanceFontSize:t.fontSize,inheritViewBox:w,viewBox:$,hasSvgAsChild:C}),b={};w||(b.viewBox=$);const d=yt(M);return k.jsxs(vt,E({as:l,className:Q(d.root,h),focusable:"false",color:g,"aria-hidden":y?void 0:!0,role:y?"img":void 0,ref:o},b,P,C&&r.props,{ownerState:M,children:[C?r.props.children:r,y?k.jsx("title",{children:y}):null]}))});Ve.muiName="SvgIcon";const je=Ve;function eo(e,t){function o(i,r){return k.jsx(je,E({"data-testid":`${t}Icon`,ref:r},i,{children:e}))}return o.muiName=je.muiName,n.memo(n.forwardRef(o))}function to(e){return Z("MuiDivider",e)}const Pt=ee("MuiDivider",["root","absolute","fullWidth","inset","middle","flexItem","light","vertical","withChildren","withChildrenVertical","textAlignRight","textAlignLeft","wrapper","wrapperVertical"]),oo=Pt;function St(e){return Z("MuiList",e)}const bt=ee("MuiList",["root","padding","dense","subheader"]),no=bt,xt=["children","className","component","dense","disablePadding","subheader"],Et=e=>{const{classes:t,disablePadding:o,dense:i,subheader:r}=e;return se({root:["root",!o&&"padding",i&&"dense",r&&"subheader"]},St,t)},wt=q("ul",{name:"MuiList",slot:"Root",overridesResolver:(e,t)=>{const{ownerState:o}=e;return[t.root,!o.disablePadding&&t.padding,o.dense&&t.dense,o.subheader&&t.subheader]}})(({ownerState:e})=>E({listStyle:"none",margin:0,padding:0,position:"relative"},!e.disablePadding&&{paddingTop:8,paddingBottom:8},e.subheader&&{paddingTop:0})),$t=n.forwardRef(function(t,o){const i=re({props:t,name:"MuiList"}),{children:r,className:h,component:u="ul",dense:l=!1,disablePadding:a=!1,subheader:g}=i,w=K(i,xt),y=n.useMemo(()=>({dense:l}),[l]),$=E({},i,{component:u,dense:l,disablePadding:a}),P=Et($);return k.jsx(ot.Provider,{value:y,children:k.jsxs(wt,E({as:u,className:Q(P.root,h),ref:o,ownerState:$},w,{children:[g,r]}))})}),Ct=$t,Mt=["actions","autoFocus","autoFocusItem","children","className","disabledItemsFocusable","disableListWrap","onKeyDown","variant"];function ye(e,t,o){return e===t?e.firstChild:t&&t.nextElementSibling?t.nextElementSibling:o?null:e.firstChild}function Ae(e,t,o){return e===t?o?e.firstChild:e.lastChild:t&&t.previousElementSibling?t.previousElementSibling:o?null:e.lastChild}function Be(e,t){if(t===void 0)return!0;let o=e.innerText;return o===void 0&&(o=e.textContent),o=o.trim().toLowerCase(),o.length===0?!1:t.repeating?o[0]===t.keys[0]:o.indexOf(t.keys.join(""))===0}function Y(e,t,o,i,r,h){let u=!1,l=r(e,t,t?o:!1);for(;l;){if(l===e.firstChild){if(u)return!1;u=!0}const a=i?!1:l.disabled||l.getAttribute("aria-disabled")==="true";if(!l.hasAttribute("tabindex")||!Be(l,h)||a)l=r(e,l,o);else return l.focus(),!0}return!1}const Rt=n.forwardRef(function(t,o){const{actions:i,autoFocus:r=!1,autoFocusItem:h=!1,children:u,className:l,disabledItemsFocusable:a=!1,disableListWrap:g=!1,onKeyDown:w,variant:y="selectedMenu"}=t,$=K(t,Mt),P=n.useRef(null),C=n.useRef({keys:[],repeating:!0,previousKeyMatched:!0,lastTime:null});nt(()=>{r&&P.current.focus()},[r]),n.useImperativeHandle(i,()=>({adjustStyleForScrollbar:(s,c)=>{const v=!P.current.style.width;if(s.clientHeight<P.current.clientHeight&&v){const R=`${rt(oe(s))}px`;P.current.style[c.direction==="rtl"?"paddingLeft":"paddingRight"]=R,P.current.style.width=`calc(100% + ${R})`}return P.current}}),[]);const M=s=>{const c=P.current,v=s.key,R=oe(c).activeElement;if(v==="ArrowDown")s.preventDefault(),Y(c,R,g,a,ye);else if(v==="ArrowUp")s.preventDefault(),Y(c,R,g,a,Ae);else if(v==="Home")s.preventDefault(),Y(c,null,g,a,ye);else if(v==="End")s.preventDefault(),Y(c,null,g,a,Ae);else if(v.length===1){const f=C.current,D=v.toLowerCase(),F=performance.now();f.keys.length>0&&(F-f.lastTime>500?(f.keys=[],f.repeating=!0,f.previousKeyMatched=!0):f.repeating&&D!==f.keys[0]&&(f.repeating=!1)),f.lastTime=F,f.keys.push(D);const W=R&&!f.repeating&&Be(R,f);f.previousKeyMatched&&(W||Y(c,R,!1,a,ye,f))?s.preventDefault():f.previousKeyMatched=!1}w&&w(s)},b=be(P,o);let d=-1;n.Children.forEach(u,(s,c)=>{if(!n.isValidElement(s)){d===c&&(d+=1,d>=u.length&&(d=-1));return}s.props.disabled||(y==="selectedMenu"&&s.props.selected||d===-1)&&(d=c),d===c&&(s.props.disabled||s.props.muiSkipListHighlight||s.type.muiSkipListHighlight)&&(d+=1,d>=u.length&&(d=-1))});const O=n.Children.map(u,(s,c)=>{if(c===d){const v={};return h&&(v.autoFocus=!0),s.props.tabIndex===void 0&&y==="selectedMenu"&&(v.tabIndex=0),n.cloneElement(s,v)}return s});return k.jsx(Ct,E({role:"menu",ref:b,className:l,onKeyDown:M,tabIndex:r?0:-1},$,{children:O}))}),Tt=Rt,It=["addEndListener","appear","children","easing","in","onEnter","onEntered","onEntering","onExit","onExited","onExiting","style","timeout","TransitionComponent"];function Se(e){return`scale(${e}, ${e**2})`}const Lt={entering:{opacity:1,transform:Se(1)},entered:{opacity:1,transform:"none"}},ve=typeof navigator<"u"&&/^((?!chrome|android).)*(safari|mobile)/i.test(navigator.userAgent)&&/(os |version\/)15(.|_)4/i.test(navigator.userAgent),Ge=n.forwardRef(function(t,o){const{addEndListener:i,appear:r=!0,children:h,easing:u,in:l,onEnter:a,onEntered:g,onEntering:w,onExit:y,onExited:$,onExiting:P,style:C,timeout:M="auto",TransitionComponent:b=st}=t,d=K(t,It),O=n.useRef(),s=n.useRef(),c=Ke(),v=n.useRef(null),R=be(v,h.ref,o),f=m=>I=>{if(m){const L=v.current;I===void 0?m(L):m(L,I)}},D=f(w),F=f((m,I)=>{it(m);const{duration:L,delay:H,easing:S}=De({style:C,timeout:M,easing:u},{mode:"enter"});let _;M==="auto"?(_=c.transitions.getAutoHeightDuration(m.clientHeight),s.current=_):_=L,m.style.transition=[c.transitions.create("opacity",{duration:_,delay:H}),c.transitions.create("transform",{duration:ve?_:_*.666,delay:H,easing:S})].join(","),a&&a(m,I)}),W=f(g),B=f(P),j=f(m=>{const{duration:I,delay:L,easing:H}=De({style:C,timeout:M,easing:u},{mode:"exit"});let S;M==="auto"?(S=c.transitions.getAutoHeightDuration(m.clientHeight),s.current=S):S=I,m.style.transition=[c.transitions.create("opacity",{duration:S,delay:L}),c.transitions.create("transform",{duration:ve?S:S*.666,delay:ve?L:L||S*.333,easing:H})].join(","),m.style.opacity=0,m.style.transform=Se(.75),y&&y(m)}),G=f($),V=m=>{M==="auto"&&(O.current=setTimeout(m,s.current||0)),i&&i(v.current,m)};return n.useEffect(()=>()=>{clearTimeout(O.current)},[]),k.jsx(b,E({appear:r,in:l,nodeRef:v,onEnter:F,onEntered:W,onEntering:D,onExit:j,onExited:G,onExiting:B,addEndListener:V,timeout:M==="auto"?null:M},d,{children:(m,I)=>n.cloneElement(h,E({style:E({opacity:0,transform:Se(.75),visibility:m==="exited"&&!l?"hidden":void 0},Lt[m],C,h.props.style),ref:R},I))}))});Ge.muiSupportAuto=!0;const _t=Ge;function zt(e){return Z("MuiPopover",e)}ee("MuiPopover",["root","paper"]);const Dt=["onEntering"],Ft=["action","anchorEl","anchorOrigin","anchorPosition","anchorReference","children","className","container","elevation","marginThreshold","open","PaperProps","slots","slotProps","transformOrigin","TransitionComponent","transitionDuration","TransitionProps","disableScrollLock"],kt=["slotProps"];function Oe(e,t){let o=0;return typeof t=="number"?o=t:t==="center"?o=e.height/2:t==="bottom"&&(o=e.height),o}function He(e,t){let o=0;return typeof t=="number"?o=t:t==="center"?o=e.width/2:t==="right"&&(o=e.width),o}function Ue(e){return[e.horizontal,e.vertical].map(t=>typeof t=="number"?`${t}px`:t).join(" ")}function Pe(e){return typeof e=="function"?e():e}const Nt=e=>{const{classes:t}=e;return se({root:["root"],paper:["paper"]},zt,t)},jt=q(lt,{name:"MuiPopover",slot:"Root",overridesResolver:(e,t)=>t.root})({}),qe=q(at,{name:"MuiPopover",slot:"Paper",overridesResolver:(e,t)=>t.paper})({position:"absolute",overflowY:"auto",overflowX:"hidden",minWidth:16,minHeight:16,maxWidth:"calc(100% - 32px)",maxHeight:"calc(100% - 32px)",outline:0}),At=n.forwardRef(function(t,o){var i,r,h;const u=re({props:t,name:"MuiPopover"}),{action:l,anchorEl:a,anchorOrigin:g={vertical:"top",horizontal:"left"},anchorPosition:w,anchorReference:y="anchorEl",children:$,className:P,container:C,elevation:M=8,marginThreshold:b=16,open:d,PaperProps:O={},slots:s,slotProps:c,transformOrigin:v={vertical:"top",horizontal:"left"},TransitionComponent:R=_t,transitionDuration:f="auto",TransitionProps:{onEntering:D}={},disableScrollLock:F=!1}=u,W=K(u.TransitionProps,Dt),B=K(u,Ft),j=(i=c==null?void 0:c.paper)!=null?i:O,G=n.useRef(),V=be(G,j.ref),m=E({},u,{anchorOrigin:g,anchorReference:y,elevation:M,marginThreshold:b,externalPaperSlotProps:j,transformOrigin:v,TransitionComponent:R,transitionDuration:f,TransitionProps:W}),I=Nt(m),L=n.useCallback(()=>{if(y==="anchorPosition")return w;const x=Pe(a),z=(x&&x.nodeType===1?x:oe(G.current).body).getBoundingClientRect();return{top:z.top+Oe(z,g.vertical),left:z.left+He(z,g.horizontal)}},[a,g.horizontal,g.vertical,w,y]),H=n.useCallback(x=>({vertical:Oe(x,v.vertical),horizontal:He(x,v.horizontal)}),[v.horizontal,v.vertical]),S=n.useCallback(x=>{const T={width:x.offsetWidth,height:x.offsetHeight},z=H(T);if(y==="none")return{top:null,left:null,transformOrigin:Ue(z)};const Re=L();let J=Re.top-z.vertical,X=Re.left-z.horizontal;const Te=J+T.height,Ie=X+T.width,Le=Fe(Pe(a)),_e=Le.innerHeight-b,ze=Le.innerWidth-b;if(b!==null&&J<b){const A=J-b;J-=A,z.vertical+=A}else if(b!==null&&Te>_e){const A=Te-_e;J-=A,z.vertical+=A}if(b!==null&&X<b){const A=X-b;X-=A,z.horizontal+=A}else if(Ie>ze){const A=Ie-ze;X-=A,z.horizontal+=A}return{top:`${Math.round(J)}px`,left:`${Math.round(X)}px`,transformOrigin:Ue(z)}},[a,y,L,H,b]),[_,we]=n.useState(d),U=n.useCallback(()=>{const x=G.current;if(!x)return;const T=S(x);T.top!==null&&(x.style.top=T.top),T.left!==null&&(x.style.left=T.left),x.style.transformOrigin=T.transformOrigin,we(!0)},[S]);n.useEffect(()=>(F&&window.addEventListener("scroll",U),()=>window.removeEventListener("scroll",U)),[a,F,U]);const Je=(x,T)=>{D&&D(x,T),U()},Xe=()=>{we(!1)};n.useEffect(()=>{d&&U()}),n.useImperativeHandle(l,()=>d?{updatePosition:()=>{U()}}:null,[d,U]),n.useEffect(()=>{if(!d)return;const x=ut(()=>{U()}),T=Fe(a);return T.addEventListener("resize",x),()=>{x.clear(),T.removeEventListener("resize",x)}},[a,d,U]);let $e=f;f==="auto"&&!R.muiSupportAuto&&($e=void 0);const Ye=C||(a?oe(Pe(a)).body:void 0),ge=(r=s==null?void 0:s.root)!=null?r:jt,Ce=(h=s==null?void 0:s.paper)!=null?h:qe,Qe=ne({elementType:Ce,externalSlotProps:E({},j,{style:_?j.style:E({},j.style,{opacity:0})}),additionalProps:{elevation:M,ref:V},ownerState:m,className:Q(I.paper,j==null?void 0:j.className)}),Me=ne({elementType:ge,externalSlotProps:(c==null?void 0:c.root)||{},externalForwardedProps:B,additionalProps:{ref:o,slotProps:{backdrop:{invisible:!0}},container:Ye,open:d},ownerState:m,className:Q(I.root,P)}),{slotProps:Ze}=Me,et=K(Me,kt);return k.jsx(ge,E({},et,!ct(ge)&&{slotProps:Ze,disableScrollLock:F},{children:k.jsx(R,E({appear:!0,in:d,onEntering:Je,onExited:Xe,timeout:$e},W,{children:k.jsx(Ce,E({},Qe,{children:$}))}))}))}),Ot=At;function Ht(e){return Z("MuiMenu",e)}ee("MuiMenu",["root","paper","list"]);const Ut=["onEntering"],Kt=["autoFocus","children","className","disableAutoFocusItem","MenuListProps","onClose","open","PaperProps","PopoverClasses","transitionDuration","TransitionProps","variant","slots","slotProps"],Wt={vertical:"top",horizontal:"right"},Vt={vertical:"top",horizontal:"left"},Bt=e=>{const{classes:t}=e;return se({root:["root"],paper:["paper"],list:["list"]},Ht,t)},Gt=q(Ot,{shouldForwardProp:e=>dt(e)||e==="classes",name:"MuiMenu",slot:"Root",overridesResolver:(e,t)=>t.root})({}),qt=q(qe,{name:"MuiMenu",slot:"Paper",overridesResolver:(e,t)=>t.paper})({maxHeight:"calc(100% - 96px)",WebkitOverflowScrolling:"touch"}),Jt=q(Tt,{name:"MuiMenu",slot:"List",overridesResolver:(e,t)=>t.list})({outline:0}),Xt=n.forwardRef(function(t,o){var i,r;const h=re({props:t,name:"MuiMenu"}),{autoFocus:u=!0,children:l,className:a,disableAutoFocusItem:g=!1,MenuListProps:w={},onClose:y,open:$,PaperProps:P={},PopoverClasses:C,transitionDuration:M="auto",TransitionProps:{onEntering:b}={},variant:d="selectedMenu",slots:O={},slotProps:s={}}=h,c=K(h.TransitionProps,Ut),v=K(h,Kt),R=Ke(),f=R.direction==="rtl",D=E({},h,{autoFocus:u,disableAutoFocusItem:g,MenuListProps:w,onEntering:b,PaperProps:P,transitionDuration:M,TransitionProps:c,variant:d}),F=Bt(D),W=u&&!g&&$,B=n.useRef(null),j=(S,_)=>{B.current&&B.current.adjustStyleForScrollbar(S,R),b&&b(S,_)},G=S=>{S.key==="Tab"&&(S.preventDefault(),y&&y(S,"tabKeyDown"))};let V=-1;n.Children.map(l,(S,_)=>{n.isValidElement(S)&&(S.props.disabled||(d==="selectedMenu"&&S.props.selected||V===-1)&&(V=_))});const m=(i=O.paper)!=null?i:qt,I=(r=s.paper)!=null?r:P,L=ne({elementType:O.root,externalSlotProps:s.root,ownerState:D,className:[F.root,a]}),H=ne({elementType:m,externalSlotProps:I,ownerState:D,className:F.paper});return k.jsx(Gt,E({onClose:y,anchorOrigin:{vertical:"bottom",horizontal:f?"right":"left"},transformOrigin:f?Wt:Vt,slots:{paper:m,root:O.root},slotProps:{root:L,paper:H},open:$,ref:o,transitionDuration:M,TransitionProps:E({onEntering:j},c),ownerState:D},v,{classes:C,children:k.jsx(Jt,E({onKeyDown:G,actions:B,autoFocus:u&&(V===-1||g),autoFocusItem:W,variant:d},w,{className:Q(F.list,w.className),children:l}))}))}),ro=Xt;export{_t as G,ro as M,Ot as P,Zt as a,eo as c,oo as d,to as g,no as l,Qt as u};
