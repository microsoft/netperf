import{_ as u,b as W,s as k,x as l,u as v,r as R,f as G,j as $,h as S,i as T,k as M,l as P,m as j}from"./index-AgPmBHmg.js";const y=["className","component","disableGutters","fixed","maxWidth","classes"],L=W(),N=k("div",{name:"MuiContainer",slot:"Root",overridesResolver:(a,s)=>{const{ownerState:o}=a;return[s.root,s[`maxWidth${l(String(o.maxWidth))}`],o.fixed&&s.fixed,o.disableGutters&&s.disableGutters]}}),_=a=>v({props:a,name:"MuiContainer",defaultTheme:L}),U=(a,s)=>{const o=i=>M(s,i),{classes:p,fixed:c,disableGutters:x,maxWidth:t}=a,e={root:["root",t&&`maxWidth${l(String(t))}`,c&&"fixed",x&&"disableGutters"]};return T(e,o,p)};function z(a={}){const{createStyledComponent:s=N,useThemeProps:o=_,componentName:p="MuiContainer"}=a,c=s(({theme:t,ownerState:e})=>u({width:"100%",marginLeft:"auto",boxSizing:"border-box",marginRight:"auto",display:"block"},!e.disableGutters&&{paddingLeft:t.spacing(2),paddingRight:t.spacing(2),[t.breakpoints.up("sm")]:{paddingLeft:t.spacing(3),paddingRight:t.spacing(3)}}),({theme:t,ownerState:e})=>e.fixed&&Object.keys(t.breakpoints.values).reduce((i,n)=>{const d=n,r=t.breakpoints.values[d];return r!==0&&(i[t.breakpoints.up(d)]={maxWidth:`${r}${t.breakpoints.unit}`}),i},{}),({theme:t,ownerState:e})=>u({},e.maxWidth==="xs"&&{[t.breakpoints.up("xs")]:{maxWidth:Math.max(t.breakpoints.values.xs,444)}},e.maxWidth&&e.maxWidth!=="xs"&&{[t.breakpoints.up(e.maxWidth)]:{maxWidth:`${t.breakpoints.values[e.maxWidth]}${t.breakpoints.unit}`}}));return R.forwardRef(function(e,i){const n=o(e),{className:d,component:r="div",disableGutters:b=!1,fixed:f=!1,maxWidth:C="lg"}=n,g=G(n,y),m=u({},n,{component:r,disableGutters:b,fixed:f,maxWidth:C}),h=U(m,p);return $.jsx(c,u({as:r,ownerState:m,className:S(h.root,d),ref:i},g))})}const E=z({createStyledComponent:P("div",{name:"MuiContainer",slot:"Root",overridesResolver:(a,s)=>{const{ownerState:o}=a;return[s.root,s[`maxWidth${l(String(o.maxWidth))}`],o.fixed&&s.fixed,o.disableGutters&&s.disableGutters]}}),useThemeProps:a=>j({props:a,name:"MuiContainer"})}),D=E;export{D as C};
