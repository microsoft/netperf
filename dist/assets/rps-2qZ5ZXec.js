import{j as a,H as r,T as d}from"./index-TGACYVrr.js";import{G as p}from"./graph-view-EFco6dx3.js";import{u as l}from"./use-fetch-data-sIUJZVMP.js";import{C as u}from"./Container-QMRD1uPo.js";import{G as c}from"./app-website-visits--vJ2IfVy.js";let i=!1;document.addEventListener("mousedown",function(){i=!0});document.addEventListener("mouseup",function(){i=!1});function b(){const o="https://raw.githubusercontent.com/microsoft/netperf/deploy/detailed_rps_and_latency_page.json",{data:t}=l(o);let s=a.jsx("div",{});if(t){const n=[];for(let e=0;e<t.linuxTcp.data.length;e++)n.push(e+1);s=a.jsx(p,{title:"Requests Per Second - Max out of 3 runs",subheader:"Tested using Windows Server 2022, Linux Ubuntu 20.04.3 LTS",labels:n,map:e=>(i&&(window.location.href=`https://github.com/microsoft/msquic/commit/${t.linuxTcp.data[e][2]}`),`<div style = "margin: 10px">

         <p> <b> Build date: </b> ${t.linuxTcp.data[e][1]} </p>
         <p> <b> Commit hash: </b> <a href="google.com"> ${t.linuxTcp.data[e][2]} </a> </p>

         <p> <b> Linux TCP: </b> ${t.linuxTcp.data[e][0]} </p>
         <p> <b> Windows TCP: </b> ${t.windowsTcp.data[e][0]} </p>
         <p> <b> Linux QUIC: </b> ${t.linuxQuic.data[e][0]} </p>
         <p> <b> Windows QUIC: </b> ${t.windowsQuic.data[e][0]} </p>

      </div>`),series:[{name:"Linux + TCP",type:"line",fill:"solid",data:t.linuxTcp.data.reverse().map(e=>e[0])},{name:"Windows + TCP",type:"line",fill:"solid",data:t.windowsTcp.data.reverse().map(e=>e[0])},{name:"Linux + QUIC",type:"line",fill:"solid",data:t.linuxQuic.data.reverse().map(e=>e[0])},{name:"Windows + QUIC",type:"line",fill:"solid",data:t.windowsQuic.data.reverse().map(e=>e[0])}]})}return a.jsxs(a.Fragment,{children:[a.jsx(r,{children:a.jsx("title",{children:" Netperf "})}),a.jsxs(u,{maxWidth:"xl",children:[a.jsx(d,{variant:"h3",sx:{mb:5},children:"Detailed Requests Per Second"}),a.jsx(c,{container:!0,spacing:3,children:s})]})]})}export{b as default};
