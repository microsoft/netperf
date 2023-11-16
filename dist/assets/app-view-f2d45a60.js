import{j as s,S as a,B as x,T as r,P as i,a as o}from"./index-04d04633.js";import{A as l}from"./app-website-visits-882e839b.js";import{f as h}from"./format-number-39bfae98.js";import{C as u}from"./Card-e0746370.js";import{C as j}from"./Container-dd49d780.js";import{G as n}from"./Grid2-5ba18c9c.js";function e({title:c,total:d,icon:t,color:g="primary",sx:p,...m}){return s.jsxs(u,{component:a,spacing:3,direction:"row",sx:{px:3,py:5,borderRadius:2,...p},...m,children:[t&&s.jsx(x,{sx:{width:64,height:64},children:t}),s.jsxs(a,{spacing:.5,children:[s.jsx(r,{variant:"h4",children:h(d)}),s.jsx(r,{variant:"subtitle2",sx:{color:"text.disabled"},children:c})]})]})}e.propTypes={color:i.string,icon:i.oneOfType([i.element,i.string]),sx:i.object,title:i.string,total:i.number};function b(){return s.jsxs(j,{maxWidth:"xl",children:[s.jsx(r,{variant:"h3",sx:{mb:5},children:"Network Performance Overview"}),s.jsx("p",{children:"Data as of 10/10/2023 (Latest Commit)"}),s.jsxs(n,{container:!0,spacing:3,children:[s.jsx(n,{xs:12,sm:6,md:3,children:s.jsx(e,{title:"Windows Throughput Performance Score.",total:107,color:"primary",icon:s.jsxs("div",{children:[s.jsx("img",{alt:"icon",src:"/netperf/dist/assets/icons/glass/windows.png"}),s.jsx(o,{onClick:()=>alert(`
                This score is computed as:

                X = Windows throughput on OpenSSL
                Y = Windows throughput on Schannel
                Z = Linux throughput on OpenSSL

                performance score = [(AVERAGE(X, Y)) / (Z)] * 100.

                Essentially, proportionally,
                Windows Throughput
                in terms of Linux.
              `),children:"?"})]})})}),s.jsx(n,{xs:12,sm:6,md:3,children:s.jsx(e,{title:"Linux Throughput Performance Score.",total:78,color:"primary",icon:s.jsxs("div",{children:[s.jsx("img",{alt:"icon",src:"/netperf/dist/assets/icons/glass/Ubuntu-Logo.png"}),s.jsx(o,{onClick:()=>alert(`
              This score is computed as:


            `),children:"?"})]})})}),s.jsx(n,{xs:12,sm:6,md:3,children:s.jsx(e,{title:"Windows Latency Performance Score.",total:80,color:"primary",icon:s.jsxs("div",{children:[s.jsx("img",{alt:"icon",src:"/netperf/dist/assets/icons/glass/windows.png"}),s.jsx(o,{onClick:()=>alert(`
                  This score is computed as:


                `),children:"?"})]})})}),s.jsx(n,{xs:12,sm:6,md:3,children:s.jsx(e,{title:"Linux Latency Performance Score.",total:79,color:"primary",icon:s.jsxs("div",{children:[s.jsx("img",{alt:"icon",src:"/netperf/dist/assets/icons/glass/Ubuntu-Logo.png"}),s.jsx(o,{onClick:()=>alert(`
              This score is computed as:


            `),children:"?"})]})})}),s.jsx(n,{xs:12,md:6,lg:6,children:s.jsx(l,{title:"Throughput Comparison (GB / s)",subheader:"Tested using Windows 11 build 22000.282, Linux Ubuntu 20.04.3 LTS",chart:{labels:["Windows + OpenSSL","Windows + Schannel","Linux + OpenSSL"],series:[{name:"TCP",type:"column",fill:"solid",data:[23,30,22]},{name:"QUIC",type:"column",fill:"solid",data:[44,55,41]}]}})}),s.jsx(n,{xs:12,md:6,lg:6,children:s.jsx(l,{title:"Latency Comparison (nanoseconds)",subheader:"Tested using Windows 11 build 22000.282, Linux Ubuntu 20.04.3 LTS",chart:{labels:["Windows + OpenSSL","Windows + Schannel","Linux + OpenSSL"],series:[{name:"TCP",type:"column",fill:"solid",data:[23,30,22]},{name:"QUIC",type:"column",fill:"solid",data:[10,5,21]}]}})})]})]})}export{b as A};
