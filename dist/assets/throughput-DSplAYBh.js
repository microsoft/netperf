import{j as i,H as r,T as s}from"./index-Pw6swrgt.js";import{u as h}from"./use-fetch-data-x099d-mF.js";import{G as n}from"./graph-view-dNUsRdQD.js";import{C as d}from"./Container-ECtAzizV.js";import{G as T}from"./app-website-visits-eSIMcWA6.js";let t=!1;document.addEventListener("mousedown",function(){t=!0});document.addEventListener("mouseup",function(){t=!1});function f(){const l="https://raw.githubusercontent.com/microsoft/netperf/deploy/detailed_throughput_page.json",{data:u}=h(l);let e=i.jsx("div",{}),a=i.jsx("div",{});if(u){const p=[];for(let o=0;o<u.linuxTcpUploadThroughput.length;o++)p.push(o+1);u.linuxTcpUploadThroughput.reverse(),u.windowsTcpUploadThroughput.reverse(),u.linuxQuicUploadThroughput.reverse(),u.windowsQuicUploadThroughput.reverse(),u.linuxTcpDownloadThroughput.reverse(),u.windowsTcpDownloadThroughput.reverse(),u.linuxQuicDownloadThroughput.reverse(),u.windowsQuicDownloadThroughput.reverse(),e=i.jsx(n,{title:"Upload Throughput",subheader:"Tested using Windows Server 2022 (Client and Server). Linux Ubuntu 20.04.3 LTS (Client and Server). WIP, NOTE: each datapoint is the max of 3 runs.",labels:p,map:o=>(t&&(window.location.href=`https://github.com/microsoft/msquic/commit/${u.linuxTcpUploadThroughput[o][2]}`),`<div style = "margin: 10px">

          NOTE: still a WIP, data is the max of 3 runs.

         <p> <b> Build date: </b> ${u.linuxTcpUploadThroughput[o][1]} </p>
         <p> <b> Commit hash: </b> <a href="google.com"> ${u.linuxTcpUploadThroughput[o][2]} </a> </p>

         <p> <b> Linux TCP: </b> ${u.linuxTcpUploadThroughput[o][0]} </p>
         <p> <b> Windows TCP: </b> ${u.windowsTcpUploadThroughput[o][0]} </p>
         <p> <b> Linux QUIC: </b> ${u.linuxQuicUploadThroughput[o][0]} </p>
         <p> <b> Windows QUIC: </b> ${u.windowsQuicUploadThroughput[o][0]} </p>

      </div>`),series:[{name:"Linux + TCP",type:"line",fill:"solid",data:u.linuxTcpUploadThroughput.map(o=>o[0])},{name:"Windows + TCP",type:"line",fill:"solid",data:u.windowsTcpUploadThroughput.map(o=>o[0])},{name:"Linux + QUIC",type:"line",fill:"solid",data:u.linuxQuicUploadThroughput.map(o=>o[0])},{name:"Windows + QUIC",type:"line",fill:"solid",data:u.windowsQuicUploadThroughput.map(o=>o[0])}]}),a=i.jsx(n,{title:"Download Throughput",subheader:"Tested using Windows Server 2022 (Client and Server). Linux Ubuntu 20.04.3 LTS (Client and Server). WIP, NOTE: each datapoint is the max of 3 runs.",labels:p,map:o=>(t&&(window.location.href=`https://github.com/microsoft/msquic/commit/${u.linuxTcpDownloadThroughput[o][2]}`),`<div style = "margin: 10px">

          NOTE: still a WIP, data is the max of 3 runs.

         <p> <b> Build date: </b> ${u.linuxTcpDownloadThroughput[o][1]} </p>
         <p> <b> Commit hash: </b> <a href="google.com"> ${u.linuxTcpDownloadThroughput[o][2]} </a> </p>

         <p> <b> Linux TCP: </b> ${u.linuxTcpDownloadThroughput[o][0]} </p>
         <p> <b> Windows TCP: </b> ${u.windowsTcpDownloadThroughput[o][0]} </p>
         <p> <b> Linux QUIC: </b> ${u.linuxQuicDownloadThroughput[o][0]} </p>
         <p> <b> Windows QUIC: </b> ${u.windowsQuicDownloadThroughput[o][0]} </p>

      </div>`),series:[{name:"Linux + TCP",type:"line",fill:"solid",data:u.linuxTcpDownloadThroughput.map(o=>o[0])},{name:"Windows + TCP",type:"line",fill:"solid",data:u.windowsTcpDownloadThroughput.map(o=>o[0])},{name:"Linux + QUIC",type:"line",fill:"solid",data:u.linuxQuicDownloadThroughput.map(o=>o[0])},{name:"Windows + QUIC",type:"line",fill:"solid",data:u.windowsQuicDownloadThroughput.map(o=>o[0])}]})}return i.jsxs(i.Fragment,{children:[i.jsx(r,{children:i.jsx("title",{children:" Netperf "})}),i.jsxs(d,{maxWidth:"xl",children:[i.jsx(s,{variant:"h3",sx:{mb:5},children:"Detailed Throughput"}),i.jsxs(T,{container:!0,spacing:3,children:[e,a]})]})]})}export{f as default};
