import{X as V,r as k,a as z,g as U,Y as N,s as v,q as g,_ as e,Z as T,u as A,b as G,j as i,c as Z,d as K,m as L,k as q,B as O,$ as X,f as b,a0 as Y,S as j,T as M,L as D,A as C,D as H,I as J,W as Q}from"./index-43a5b071.js";import{C as oo}from"./Card-056eff48.js";import{D as to}from"./Divider-0c7e5b9c.js";import{T as E}from"./TextField-8c99976f.js";import{u as io}from"./Menu-63248d8d.js";import"./isMuiElement-85a2be06.js";import"./Select-999ef013.js";function ro(){const t=V();return k.useMemo(()=>({back:()=>t(-1),forward:()=>t(1),reload:()=>window.location.reload(),push:r=>t(r),replace:r=>t(r,{replace:!0})}),[t])}function no(t){return z("MuiCircularProgress",t)}U("MuiCircularProgress",["root","determinate","indeterminate","colorPrimary","colorSecondary","svg","circle","circleDeterminate","circleIndeterminate","circleDisableShrink"]);const ao=["className","color","disableShrink","size","style","thickness","value","variant"];let $=t=>t,W,w,F,_;const c=44,so=N(W||(W=$`
  0% {
    transform: rotate(0deg);
  }

  100% {
    transform: rotate(360deg);
  }
`)),eo=N(w||(w=$`
  0% {
    stroke-dasharray: 1px, 200px;
    stroke-dashoffset: 0;
  }

  50% {
    stroke-dasharray: 100px, 200px;
    stroke-dashoffset: -15px;
  }

  100% {
    stroke-dasharray: 100px, 200px;
    stroke-dashoffset: -125px;
  }
`)),lo=t=>{const{classes:o,variant:r,color:n,disableShrink:a}=t,s={root:["root",r,`color${g(n)}`],svg:["svg"],circle:["circle",`circle${g(r)}`,a&&"circleDisableShrink"]};return K(s,no,o)},co=v("span",{name:"MuiCircularProgress",slot:"Root",overridesResolver:(t,o)=>{const{ownerState:r}=t;return[o.root,o[r.variant],o[`color${g(r.color)}`]]}})(({ownerState:t,theme:o})=>e({display:"inline-block"},t.variant==="determinate"&&{transition:o.transitions.create("transform")},t.color!=="inherit"&&{color:(o.vars||o).palette[t.color].main}),({ownerState:t})=>t.variant==="indeterminate"&&T(F||(F=$`
      animation: ${0} 1.4s linear infinite;
    `),so)),go=v("svg",{name:"MuiCircularProgress",slot:"Svg",overridesResolver:(t,o)=>o.svg})({display:"block"}),uo=v("circle",{name:"MuiCircularProgress",slot:"Circle",overridesResolver:(t,o)=>{const{ownerState:r}=t;return[o.circle,o[`circle${g(r.variant)}`],r.disableShrink&&o.circleDisableShrink]}})(({ownerState:t,theme:o})=>e({stroke:"currentColor"},t.variant==="determinate"&&{transition:o.transitions.create("stroke-dashoffset")},t.variant==="indeterminate"&&{strokeDasharray:"80px, 200px",strokeDashoffset:0}),({ownerState:t})=>t.variant==="indeterminate"&&!t.disableShrink&&T(_||(_=$`
      animation: ${0} 1.4s ease-in-out infinite;
    `),eo)),ho=k.forwardRef(function(o,r){const n=A({props:o,name:"MuiCircularProgress"}),{className:a,color:s="primary",disableShrink:B=!1,size:u=40,style:I,thickness:x=3.6,value:f=0,variant:y="indeterminate"}=n,P=G(n,ao),h=e({},n,{color:s,disableShrink:B,size:u,thickness:x,value:f,variant:y}),l=lo(h),p={},m={},R={};if(y==="determinate"){const S=2*Math.PI*((c-x)/2);p.strokeDasharray=S.toFixed(3),R["aria-valuenow"]=Math.round(f),p.strokeDashoffset=`${((100-f)/100*S).toFixed(3)}px`,m.transform="rotate(-90deg)"}return i.jsx(co,e({className:Z(l.root,a),style:e({width:u,height:u},m,I),ownerState:h,ref:r,role:"progressbar"},R,P,{children:i.jsx(go,{className:l.svg,ownerState:h,viewBox:`${c/2} ${c/2} ${c} ${c}`,children:i.jsx(uo,{className:l.circle,style:p,ownerState:h,cx:c,cy:c,r:(c-x)/2,fill:"none",strokeWidth:x})})}))}),xo=ho;function fo(t){return z("MuiLoadingButton",t)}const po=U("MuiLoadingButton",["root","loading","loadingIndicator","loadingIndicatorCenter","loadingIndicatorStart","loadingIndicatorEnd","endIconLoadingEnd","startIconLoadingStart"]),d=po,mo=["children","disabled","id","loading","loadingIndicator","loadingPosition","variant"],vo=t=>{const{loading:o,loadingPosition:r,classes:n}=t,a={root:["root",o&&"loading"],startIcon:[o&&`startIconLoading${g(r)}`],endIcon:[o&&`endIconLoading${g(r)}`],loadingIndicator:["loadingIndicator",o&&`loadingIndicator${g(r)}`]},s=K(a,fo,n);return e({},n,s)},Io=t=>t!=="ownerState"&&t!=="theme"&&t!=="sx"&&t!=="as"&&t!=="classes",yo=v(L,{shouldForwardProp:t=>Io(t)||t==="classes",name:"MuiLoadingButton",slot:"Root",overridesResolver:(t,o)=>[o.root,o.startIconLoadingStart&&{[`& .${d.startIconLoadingStart}`]:o.startIconLoadingStart},o.endIconLoadingEnd&&{[`& .${d.endIconLoadingEnd}`]:o.endIconLoadingEnd}]})(({ownerState:t,theme:o})=>e({[`& .${d.startIconLoadingStart}, & .${d.endIconLoadingEnd}`]:{transition:o.transitions.create(["opacity"],{duration:o.transitions.duration.short}),opacity:0}},t.loadingPosition==="center"&&{transition:o.transitions.create(["background-color","box-shadow","border-color"],{duration:o.transitions.duration.short}),[`&.${d.loading}`]:{color:"transparent"}},t.loadingPosition==="start"&&t.fullWidth&&{[`& .${d.startIconLoadingStart}, & .${d.endIconLoadingEnd}`]:{transition:o.transitions.create(["opacity"],{duration:o.transitions.duration.short}),opacity:0,marginRight:-8}},t.loadingPosition==="end"&&t.fullWidth&&{[`& .${d.startIconLoadingStart}, & .${d.endIconLoadingEnd}`]:{transition:o.transitions.create(["opacity"],{duration:o.transitions.duration.short}),opacity:0,marginLeft:-8}})),Po=v("span",{name:"MuiLoadingButton",slot:"LoadingIndicator",overridesResolver:(t,o)=>{const{ownerState:r}=t;return[o.loadingIndicator,o[`loadingIndicator${g(r.loadingPosition)}`]]}})(({theme:t,ownerState:o})=>e({position:"absolute",visibility:"visible",display:"flex"},o.loadingPosition==="start"&&(o.variant==="outlined"||o.variant==="contained")&&{left:o.size==="small"?10:14},o.loadingPosition==="start"&&o.variant==="text"&&{left:6},o.loadingPosition==="center"&&{left:"50%",transform:"translate(-50%)",color:(t.vars||t).palette.action.disabled},o.loadingPosition==="end"&&(o.variant==="outlined"||o.variant==="contained")&&{right:o.size==="small"?10:14},o.loadingPosition==="end"&&o.variant==="text"&&{right:6},o.loadingPosition==="start"&&o.fullWidth&&{position:"relative",left:-10},o.loadingPosition==="end"&&o.fullWidth&&{position:"relative",right:-10})),bo=k.forwardRef(function(o,r){const n=A({props:o,name:"MuiLoadingButton"}),{children:a,disabled:s=!1,id:B,loading:u=!1,loadingIndicator:I,loadingPosition:x="center",variant:f="text"}=n,y=G(n,mo),P=io(B),h=I??i.jsx(xo,{"aria-labelledby":P,color:"inherit",size:16}),l=e({},n,{disabled:s,loading:u,loadingIndicator:h,loadingPosition:x,variant:f}),p=vo(l),m=u?i.jsx(Po,{className:p.loadingIndicator,ownerState:l,children:h}):null;return i.jsxs(yo,e({disabled:s||u,id:P,ref:r},y,{variant:f,classes:p,ownerState:l,children:[l.loadingPosition==="end"?a:m,l.loadingPosition==="end"?m:a]}))}),jo=bo;function Co(){const t=q(),o=ro(),[r,n]=k.useState(!1),a=()=>{o.push("/dashboard")},s=i.jsxs(i.Fragment,{children:[i.jsxs(j,{spacing:3,children:[i.jsx(E,{name:"email",label:"Email address"}),i.jsx(E,{name:"password",label:"Password",type:r?"text":"password",InputProps:{endAdornment:i.jsx(H,{position:"end",children:i.jsx(J,{onClick:()=>n(!r),edge:"end",children:i.jsx(C,{icon:r?"eva:eye-fill":"eva:eye-off-fill"})})})}})]}),i.jsx(j,{direction:"row",alignItems:"center",justifyContent:"flex-end",sx:{my:3},children:i.jsx(D,{variant:"subtitle2",underline:"hover",children:"Forgot password?"})}),i.jsx(jo,{fullWidth:!0,size:"large",type:"submit",variant:"contained",color:"inherit",onClick:a,children:"Login"})]});return i.jsxs(O,{sx:{...X({color:b(t.palette.background.default,.9),imgUrl:"/assets/background/overlay_4.jpg"}),height:1},children:[i.jsx(Y,{sx:{position:"fixed",top:{xs:16,md:24},left:{xs:16,md:24}}}),i.jsx(j,{alignItems:"center",justifyContent:"center",sx:{height:1},children:i.jsxs(oo,{sx:{p:5,width:1,maxWidth:420},children:[i.jsx(M,{variant:"h4",children:"Sign in to Minimal"}),i.jsxs(M,{variant:"body2",sx:{mt:2,mb:5},children:["Don’t have an account?",i.jsx(D,{variant:"subtitle2",sx:{ml:.5},children:"Get started"})]}),i.jsxs(j,{direction:"row",spacing:2,children:[i.jsx(L,{fullWidth:!0,size:"large",color:"inherit",variant:"outlined",sx:{borderColor:b(t.palette.grey[500],.16)},children:i.jsx(C,{icon:"eva:google-fill",color:"#DF3E30"})}),i.jsx(L,{fullWidth:!0,size:"large",color:"inherit",variant:"outlined",sx:{borderColor:b(t.palette.grey[500],.16)},children:i.jsx(C,{icon:"eva:facebook-fill",color:"#1877F2"})}),i.jsx(L,{fullWidth:!0,size:"large",color:"inherit",variant:"outlined",sx:{borderColor:b(t.palette.grey[500],.16)},children:i.jsx(C,{icon:"eva:twitter-fill",color:"#1C9CEA"})})]}),i.jsx(to,{sx:{my:3},children:i.jsx(M,{variant:"body2",sx:{color:"text.secondary"},children:"OR"})}),s]})})]})}function Do(){return i.jsxs(i.Fragment,{children:[i.jsx(Q,{children:i.jsx("title",{children:" Login | Minimal UI "})}),i.jsx(Co,{})]})}export{Do as default};
