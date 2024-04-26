import{r as c,j as e,H as k,T as O,B as d}from"./index-_oLpBMG5.js";import{u as Q,F as p,I as u,S as m,M as o,G as R}from"./app-website-visits-2FRUA6tG.js";import{G as z}from"./graph-view-i5McUyzM.js";import{C as D}from"./Container-Zt9ly0CE.js";let j=!1;document.addEventListener("mousedown",function(){j=!0});document.addEventListener("mouseup",function(){j=!1});function B(){const y="https://raw.githubusercontent.com/microsoft/netperf/deploy/historical_rps_page.json",{data:n}=Q(y);let w=e.jsx("div",{});const[t,I]=c.useState("azure"),[i,T]=c.useState("windows-2022-x64"),[r,L]=c.useState("ubuntu-20.04-x64"),[a,S]=c.useState("rps-up-512-down-4000");if(n){let l=n[`${i}-${t}-iocp-schannel`][`${a}-tcp`].data.slice().reverse(),g=n[`${r}-${t}-epoll-openssl`][`${a}-tcp`].data.slice().reverse(),C=Array.from({length:Math.max(l.length,g.length)},(s,W)=>W);C.reverse();const h=n[`${i}-${t}-iocp-schannel`][`${a}-tcp`].data.slice().reverse(),x=n[`${i}-${t}-iocp-schannel`][`${a}-quic`].data.slice().reverse(),b=n[`${r}-${t}-epoll-openssl`][`${a}-tcp`].data.slice().reverse(),v=n[`${r}-${t}-epoll-openssl`][`${a}-quic`].data.slice().reverse(),$=n[`${i}-${t}-xdp-schannel`][`${a}-quic`].data.slice().reverse(),f=n[`${i}-${t}-wsk-schannel`][`${a}-quic`].data.slice().reverse();w=e.jsx(z,{title:"Requests Per Second Throughput",subheader:`Tested using ${i}, ${r}, taking the max of 3 runs. `,labels:C,map:s=>(j&&(window.location.href=`https://github.com/microsoft/msquic/commit/${l[s][1]}`),`<div style = "margin: 10px">

         <p> <b> Build date: </b> ${l[s][3]} </p>
         <p> <b> Specific Windows OS version this test ran on: </b> ${l[s][2]} </p>
         <p> <b> Specific Linux OS version this test ran on: </b> ${g[s][2]} </p>
         <p> <b> Commit hash: </b> <a href="google.com"> ${l[s][1]} </a> </p>

         <p> <b> TCP + iocp: </b> ${h[s]&&h[s][0]}, </p>
         <p> <b> QUIC + iocp: </b> ${x[s]&&x[s][0]} </p>
         <p> <b> TCP + epoll: </b> ${b[s]&&b[s][0]} </p>
         <p> <b> QUIC + epoll: </b> ${v[s]&&v[s][0]},
         <b> QUIC + winXDP: </b> ${$[s]&&$[s][0]},
         <b> QUIC + wsk: </b> ${f[s]&&f[s][0]} </p>
      </div>`),series:[{name:"TCP + iocp",type:"line",fill:"solid",data:h.map(s=>s[0])},{name:"QUIC + iocp",type:"line",fill:"solid",data:x},{name:"TCP + epoll",type:"line",fill:"solid",data:b},{name:"QUIC + epoll",type:"line",fill:"solid",data:v},{name:"QUIC + winXDP",type:"line",fill:"solid",data:$},{name:"QUIC + wsk",type:"line",fill:"solid",data:f}],options:{markers:{size:5}}})}const q=l=>{I(l.target.value)},E=l=>{T(l.target.value)},P=l=>{L(l.target.value)},U=l=>{S(l.target.value)};return e.jsxs(e.Fragment,{children:[e.jsx(k,{children:e.jsx("title",{children:" Netperf "})}),e.jsxs(D,{maxWidth:"xl",children:[e.jsx(O,{variant:"h3",sx:{mb:5},children:"Detailed Requests Per Second"}),e.jsxs("div",{style:{display:"flex"},children:[e.jsx(d,{sx:{},children:e.jsxs(p,{children:[e.jsx(u,{id:"demo-simple-select-label",children:"Context"}),e.jsxs(m,{labelId:"demo-simple-select-label",id:"demo-simple-select",value:t,label:"Context",onChange:q,defaultValue:0,children:[e.jsx(o,{value:"azure",children:"azure"}),i!=="windows-2025-x64"&&e.jsx(o,{value:"lab",children:"lab"})]})]})}),e.jsx(d,{sx:{minWidth:120,marginLeft:"10px"},children:e.jsxs(p,{children:[e.jsx(u,{id:"demo-simple-select-label",children:"Windows Environment"}),e.jsxs(m,{labelId:"demo-simple-select-label",id:"demo-simple-select",value:i,label:"Windows Environment",onChange:E,defaultValue:0,children:[e.jsx(o,{value:"windows-2022-x64",children:"windows-2022-x64"}),t==="azure"&&e.jsx(o,{value:"windows-2025-x64",children:"windows-2025-x64"})]})]})}),e.jsx(d,{sx:{minWidth:120,marginLeft:"10px"},children:e.jsxs(p,{children:[e.jsx(u,{id:"demo-simple-select-label",children:"Linux Environment"}),e.jsx(m,{labelId:"demo-simple-select-label",id:"demo-simple-select",value:r,label:"Linux Environment",onChange:P,defaultValue:0,children:e.jsx(o,{value:"ubuntu-20.04-x64",children:"ubuntu-20.04-x64"})})]})}),e.jsx(d,{sx:{minWidth:120,marginLeft:"10px"},children:e.jsxs(p,{children:[e.jsx(u,{id:"demo-simple-select-label",children:"Test type"}),e.jsx(m,{labelId:"demo-simple-select-label",id:"demo-simple-select",value:a,label:"test type",onChange:U,defaultValue:0,children:e.jsx(o,{value:"rps-up-512-down-4000",children:"512 kb upload, 4000 kb download"})})]})})]}),e.jsx("br",{}),e.jsx(R,{container:!0,spacing:3,children:w})]})]})}export{B as default};
