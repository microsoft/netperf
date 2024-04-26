import{r as c,j as e,H as Q,T as D,B as p}from"./index-_oLpBMG5.js";import{u as P,F as d,I as u,S as h,M as o,G as k}from"./app-website-visits-2FRUA6tG.js";import{G as z}from"./graph-view-i5McUyzM.js";import{C as V}from"./Container-Zt9ly0CE.js";let j=!1;document.addEventListener("mousedown",function(){j=!0});document.addEventListener("mouseup",function(){j=!1});function R(){const y="https://raw.githubusercontent.com/microsoft/netperf/deploy/historical_throughput_page.json",{data:a}=P(y);let g=e.jsx("div",{});const[t,T]=c.useState("azure"),[i,I]=c.useState("windows-2022-x64"),[r,L]=c.useState("ubuntu-20.04-x64"),[n,U]=c.useState("up");if(a){let l=a[`${i}-${t}-iocp-schannel`][`tput-${n}-tcp`].data.slice().reverse(),w=a[`${r}-${t}-epoll-openssl`][`tput-${n}-tcp`].data.slice().reverse(),C=Array.from({length:Math.max(l.length,w.length)},(s,O)=>O);C.reverse();const m=a[`${i}-${t}-iocp-schannel`][`tput-${n}-tcp`].data.slice().reverse(),x=a[`${i}-${t}-iocp-schannel`][`tput-${n}-quic`].data.slice().reverse(),b=a[`${r}-${t}-epoll-openssl`][`tput-${n}-tcp`].data.slice().reverse(),v=a[`${r}-${t}-epoll-openssl`][`tput-${n}-quic`].data.slice().reverse(),$=a[`${i}-${t}-xdp-schannel`][`tput-${n}-quic`].data.slice().reverse(),f=a[`${i}-${t}-wsk-schannel`][`tput-${n}-quic`].data.slice().reverse();g=e.jsx(z,{title:`${n==="up"?"Upload":"Download"} Throughput`,subheader:`Tested using ${i}, ${r}, taking the max of 3 runs. `,labels:C,map:s=>(j&&(window.location.href=`https://github.com/microsoft/msquic/commit/${l[s][1]}`),`<div style = "margin: 10px">

         <p> <b> Build date: </b> ${l[s][3]} </p>
         <p> <b> Specific Windows OS version this test ran on: </b> ${l[s][2]} </p>
         <p> <b> Specific Linux OS version this test ran on: </b> ${w[s][2]} </p>
         <p> <b> Commit hash: </b> <a href="google.com"> ${l[s][1]} </a> </p>

         <p> <b> TCP + iocp: </b> ${m[s]&&m[s][0]}, </p>
         <p> <b> QUIC + iocp: </b> ${x[s]&&x[s][0]} </p>
         <p> <b> TCP + epoll: </b> ${b[s]&&b[s][0]} </p>
         <p> <b> QUIC + epoll: </b> ${v[s]&&v[s][0]},
         <b> QUIC + winXDP: </b> ${$[s]&&$[s][0]},
         <b> QUIC + wsk: </b> ${f[s]&&f[s][0]} </p>
      </div>`),series:[{name:"TCP + iocp",type:"line",fill:"solid",data:m.map(s=>s[0])},{name:"QUIC + iocp",type:"line",fill:"solid",data:x},{name:"TCP + epoll",type:"line",fill:"solid",data:b},{name:"QUIC + epoll",type:"line",fill:"solid",data:v},{name:"QUIC + winXDP",type:"line",fill:"solid",data:$},{name:"QUIC + wsk",type:"line",fill:"solid",data:f}],options:{markers:{size:5}}})}const S=l=>{T(l.target.value)},q=l=>{I(l.target.value)},E=l=>{L(l.target.value)},W=l=>{U(l.target.value)};return e.jsxs(e.Fragment,{children:[e.jsx(Q,{children:e.jsx("title",{children:" Netperf "})}),e.jsxs(V,{maxWidth:"xl",children:[e.jsx(D,{variant:"h3",sx:{mb:5},children:"Detailed Throughput"}),e.jsxs("div",{style:{display:"flex"},children:[e.jsx(p,{sx:{},children:e.jsxs(d,{children:[e.jsx(u,{id:"demo-simple-select-label",children:"Context"}),e.jsxs(h,{labelId:"demo-simple-select-label",id:"demo-simple-select",value:t,label:"Context",onChange:S,defaultValue:0,children:[e.jsx(o,{value:"azure",children:"azure"}),i!=="windows-2025-x64"&&e.jsx(o,{value:"lab",children:"lab"})]})]})}),e.jsx(p,{sx:{minWidth:120,marginLeft:"10px"},children:e.jsxs(d,{children:[e.jsx(u,{id:"demo-simple-select-label",children:"Windows Environment"}),e.jsxs(h,{labelId:"demo-simple-select-label",id:"demo-simple-select",value:i,label:"Windows Environment",onChange:q,defaultValue:0,children:[e.jsx(o,{value:"windows-2022-x64",children:"windows-2022-x64"}),t==="azure"&&e.jsx(o,{value:"windows-2025-x64",children:"windows-2025-x64"})]})]})}),e.jsx(p,{sx:{minWidth:120,marginLeft:"10px"},children:e.jsxs(d,{children:[e.jsx(u,{id:"demo-simple-select-label",children:"Linux Environment"}),e.jsx(h,{labelId:"demo-simple-select-label",id:"demo-simple-select",value:r,label:"Linux Environment",onChange:E,defaultValue:0,children:e.jsx(o,{value:"ubuntu-20.04-x64",children:"ubuntu-20.04-x64"})})]})}),e.jsx(p,{sx:{minWidth:120,marginLeft:"10px"},children:e.jsxs(d,{children:[e.jsx(u,{id:"demo-simple-select-label",children:"Test type"}),e.jsxs(h,{labelId:"demo-simple-select-label",id:"demo-simple-select",value:n,label:"Upload or download",onChange:W,defaultValue:0,children:[e.jsx(o,{value:"up",children:"Upload - 1 connection, 12 seconds per run"}),e.jsx(o,{value:"down",children:"Download - 1 connection, 12 seconds per run"})]})]})})]}),e.jsx("br",{}),e.jsx(k,{container:!0,spacing:3,children:g})]})]})}export{R as default};
