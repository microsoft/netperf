import{_ as u,ai as W,aj as k,q as l,ak as v,r as R,b as G,j as $,c as S,d as T,a as j,s as M,u as P}from"./index-43a5b071.js";const y=["className","component","disableGutters","fixed","maxWidth","classes"],L=W(),N=k("div",{name:"MuiContainer",slot:"Root",overridesResolver:(a,e)=>{const{ownerState:o}=a;return[e.root,e[`maxWidth${l(String(o.maxWidth))}`],o.fixed&&e.fixed,o.disableGutters&&e.disableGutters]}}),_=a=>v({props:a,name:"MuiContainer",defaultTheme:L}),U=(a,e)=>{const o=i=>j(e,i),{classes:c,fixed:p,disableGutters:x,maxWidth:t}=a,s={root:["root",t&&`maxWidth${l(String(t))}`,p&&"fixed",x&&"disableGutters"]};return T(s,o,c)};function w(a={}){const{createStyledComponent:e=N,useThemeProps:o=_,componentName:c="MuiContainer"}=a,p=e(({theme:t,ownerState:s})=>u({width:"100%",marginLeft:"auto",boxSizing:"border-box",marginRight:"auto",display:"block"},!s.disableGutters&&{paddingLeft:t.spacing(2),paddingRight:t.spacing(2),[t.breakpoints.up("sm")]:{paddingLeft:t.spacing(3),paddingRight:t.spacing(3)}}),({theme:t,ownerState:s})=>s.fixed&&Object.keys(t.breakpoints.values).reduce((i,n)=>{const d=n,r=t.breakpoints.values[d];return r!==0&&(i[t.breakpoints.up(d)]={maxWidth:`${r}${t.breakpoints.unit}`}),i},{}),({theme:t,ownerState:s})=>u({},s.maxWidth==="xs"&&{[t.breakpoints.up("xs")]:{maxWidth:Math.max(t.breakpoints.values.xs,444)}},s.maxWidth&&s.maxWidth!=="xs"&&{[t.breakpoints.up(s.maxWidth)]:{maxWidth:`${t.breakpoints.values[s.maxWidth]}${t.breakpoints.unit}`}}));return R.forwardRef(function(s,i){const n=o(s),{className:d,component:r="div",disableGutters:b=!1,fixed:f=!1,maxWidth:C="lg"}=n,g=G(n,y),m=u({},n,{component:r,disableGutters:b,fixed:f,maxWidth:C}),h=U(m,c);return $.jsx(p,u({as:r,ownerState:m,className:S(h.root,d),ref:i},g))})}const z=w({createStyledComponent:M("div",{name:"MuiContainer",slot:"Root",overridesResolver:(a,e)=>{const{ownerState:o}=a;return[e.root,e[`maxWidth${l(String(o.maxWidth))}`],o.fixed&&e.fixed,o.disableGutters&&e.disableGutters]}}),useThemeProps:a=>P({props:a,name:"MuiContainer"})}),q=z;export{q as C};
