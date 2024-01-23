import{j as t,W as r,T as s}from"./index-mMppD5v3.js";import{u as h}from"./use-fetch-data-mLPsZ3tO.js";import{G as l}from"./graph-view-j-3qV4MW.js";import{C as d}from"./Container-Hi_mH3Do.js";import{G as T}from"./app-website-visits-ORVnn8MZ.js";let u=!1;document.addEventListener("mousedown",function(){u=!0});document.addEventListener("mouseup",function(){u=!1});function x(){const e="https://raw.githubusercontent.com/microsoft/netperf/deploy/throughput.json",{data:i}=h(e);let a=t.jsx("div",{}),n=t.jsx("div",{});if(i){const p=[];for(let o=0;o<i.linuxTcpUploadThroughput.length;o++)p.push(o+1);i.linuxTcpUploadThroughput.reverse(),a=t.jsx(l,{title:"Upload Throughput",subheader:"Tested using Windows Server 2022 (Client and Server). Linux Ubuntu 20.04.3 LTS (Client and Server). WIP, NOTE: each datapoint is the max of 3 runs.",labels:p,map:o=>(u&&(window.location.href=`https://github.com/microsoft/msquic/commit/${i.linuxTcpUploadThroughput[o][2]}`),`<div style = "margin: 10px">

          NOTE: still a WIP, data is the max of 3 runs.

         <p> <b> Build date: </b> ${i.linuxTcpUploadThroughput[o][1]} </p>
         <p> <b> Commit hash: </b> <a href="google.com"> ${i.linuxTcpUploadThroughput[o][2]} </a> </p>

         <p> <b> Linux TCP: </b> ${i.linuxTcpUploadThroughput[o][0]} </p>
         <p> <b> Windows TCP: </b> ${i.windowsTcpUploadThroughput[o][0]} </p>
         <p> <b> Linux QUIC: </b> ${i.linuxQuicUploadThroughput[o][0]} </p>
         <p> <b> Windows QUIC: </b> ${i.windowsQuicUploadThroughput[o][0]} </p>

      </div>`),series:[{name:"Linux + TCP",type:"line",fill:"solid",data:i.linuxTcpUploadThroughput.map(o=>o[0])},{name:"Windows + TCP",type:"line",fill:"solid",data:i.windowsTcpUploadThroughput.map(o=>o[0])},{name:"Linux + QUIC",type:"line",fill:"solid",data:i.linuxQuicUploadThroughput.map(o=>o[0])},{name:"Windows + QUIC",type:"line",fill:"solid",data:i.windowsQuicUploadThroughput.map(o=>o[0])}]}),n=t.jsx(l,{title:"Download Throughput",subheader:"Tested using Windows Server 2022 (Client and Server). Linux Ubuntu 20.04.3 LTS (Client and Server). WIP, NOTE: each datapoint is the max of 3 runs.",labels:p,map:o=>(u&&(window.location.href=`https://github.com/microsoft/msquic/commit/${i.linuxTcpDownloadThroughput[o][2]}`),`<div style = "margin: 10px">

          NOTE: still a WIP, data is the max of 3 runs.

         <p> <b> Build date: </b> ${i.linuxTcpDownloadThroughput[o][1]} </p>
         <p> <b> Commit hash: </b> <a href="google.com"> ${i.linuxTcpDownloadThroughput[o][2]} </a> </p>

         <p> <b> Linux TCP: </b> ${i.linuxTcpDownloadThroughput[o][0]} </p>
         <p> <b> Windows TCP: </b> ${i.windowsTcpDownloadThroughput[o][0]} </p>
         <p> <b> Linux QUIC: </b> ${i.linuxQuicDownloadThroughput[o][0]} </p>
         <p> <b> Windows QUIC: </b> ${i.windowsQuicDownloadThroughput[o][0]} </p>

      </div>`),series:[{name:"Linux + TCP",type:"line",fill:"solid",data:i.linuxTcpDownloadThroughput.map(o=>o[0])},{name:"Windows + TCP",type:"line",fill:"solid",data:i.windowsTcpDownloadThroughput.map(o=>o[0])},{name:"Linux + QUIC",type:"line",fill:"solid",data:i.linuxQuicDownloadThroughput.map(o=>o[0])},{name:"Windows + QUIC",type:"line",fill:"solid",data:i.windowsQuicDownloadThroughput.map(o=>o[0])}]})}return t.jsxs(t.Fragment,{children:[t.jsx(r,{children:t.jsx("title",{children:" Netperf "})}),t.jsxs(d,{maxWidth:"xl",children:[t.jsx(s,{variant:"h3",sx:{mb:5},children:"Detailed Throughput"}),t.jsxs(T,{container:!0,spacing:3,children:[a,n]})]})]})}export{x as default};
