import{r as s,j as t,H as j}from"./index-sAcdVDxi.js";const h={};let x=0;const S=c=>{const[o,u]=s.useState(null),[l,n]=s.useState(!1),[i,a]=s.useState(null),[d,p]=s.useState(null);return s.useEffect(()=>{let r="https://microsoft.github.io/netperf/wasm_worker.js";const e=new Worker(r);return e.onmessage=y=>{const{type:k,error:g,results:b,id:m}=y.data;switch(k){case"ready":n(!0),a(b);break;case"error":p(g);break;case"execResult":h[m](b);break}},e.postMessage({type:"init",url:c}),u(e),()=>{e.terminate()}},[c]),{exec:(r,e)=>{x+=1,h[x]=e,o&&l?o.postMessage({type:"exec",sql:r,call_id:x}):console.error("Database is not ready or worker is not set up")},isReady:l,db:i,err:d}},w=S;function E(c){const{exec:o,isReady:u,error:l}=w("https://raw.githubusercontent.com/microsoft/netperf/sqlite/netperf.sqlite"),[n,i]=s.useState(null);s.useEffect(()=>{console.log("Data: ",n)},[n]);const[a,d]=s.useState(""),p=e=>{if(!u){console.log("Database is not ready");return}o(e,i)},f=e=>{d(e.target.value)},r=()=>{p(a)};return t.jsxs(t.Fragment,{children:[t.jsx(j,{children:t.jsx("title",{children:" Detailed Page "})}),t.jsxs("div",{children:[t.jsx("input",{type:"text",value:a,onChange:f,placeholder:"Enter SQL query"}),t.jsx("br",{}),t.jsx("button",{onClick:r,children:"Execute Query"}),t.jsx("br",{}),"Look in the browser console for the full data output via inspect element.",t.jsx("br",{})]})]})}export{E as default};