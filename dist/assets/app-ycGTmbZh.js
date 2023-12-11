import{r as p,j as s,S as f,B as T,T as x,P as t,a as u,W as L}from"./index-nzTyfD75.js";import{A as y}from"./app-website-visits-XiFfxrYq.js";import{f as b}from"./format-number-rKLGW4eg.js";import{C}from"./Card-K074Xi4C.js";import{C as P}from"./Container-0Z27z7Xj.js";import{G as n}from"./Grid2-jktIMNj9.js";import"./isMuiElement-Y9hTFdtc.js";function W(o){const[l,i]=p.useState(null),[d,r]=p.useState(!0),[a,h]=p.useState(null);return p.useEffect(()=>{fetch(o).then(e=>{if(!e.ok)throw new Error("Network response was not ok");return e.json()}).then(e=>{i(e),r(!1)}).catch(e=>{h(e),r(!1)})},[o]),{data:l,isLoading:d,error:a}}function c({title:o,total:l,icon:i,color:d="primary",sx:r,...a}){return s.jsxs(C,{component:f,spacing:3,direction:"row",sx:{px:3,py:5,borderRadius:2,...r},...a,children:[i&&s.jsx(T,{sx:{width:64,height:64},children:i}),s.jsxs(f,{spacing:.5,children:[s.jsx(x,{variant:"h4",children:b(l)}),s.jsx(x,{variant:"subtitle2",sx:{color:"text.disabled"},children:o})]})]})}c.propTypes={color:t.string,icon:t.oneOfType([t.element,t.string]),sx:t.object,title:t.string,total:t.number};function k(){const{data:o,isLoading:l,error:i}=W("https://raw.githubusercontent.com/projectsbyjackhe/netperf/deploy/landing_page.json"),d=0,r=0,a=0,h=0;let e=0,m=0,w=0,g=0,j="";const S="";return o&&(j=o.windows.type,w=o.windows.download_throughput_quic,g=o.windows.download_throughput_tcp,e=o.windows.upload_throughput_quic,m=o.windows.upload_throughput_tcp),s.jsxs(P,{maxWidth:"xl",children:[s.jsx(x,{variant:"h3",sx:{mb:5},children:"Network Performance Overview"}),s.jsx("p",{children:"Data as of 10/10/2023 (Latest Commit)"}),s.jsxs(n,{container:!0,spacing:3,children:[s.jsx(n,{xs:12,sm:6,md:3,children:s.jsx(c,{title:"Windows Throughput Performance Score.",total:d,color:"primary",icon:s.jsxs("div",{children:[s.jsx("img",{alt:"icon",src:"/netperf/dist/assets/icons/glass/windows.png"}),s.jsx(u,{onClick:()=>alert(`
                This score is computed as:

                X = Windows throughput on OpenSSL
                Y = Windows throughput on Schannel
                Z = Linux throughput on OpenSSL

                performance score = [(AVERAGE(X, Y)) / (Z)] * 100.

                Essentially, proportionally,
                Windows Throughput
                in terms of Linux.
              `),children:"?"})]})})}),s.jsx(n,{xs:12,sm:6,md:3,children:s.jsx(c,{title:"Linux Throughput Performance Score.",total:r,color:"primary",icon:s.jsxs("div",{children:[s.jsx("img",{alt:"icon",src:"/netperf/dist/assets/icons/glass/Ubuntu-Logo.png"}),s.jsx(u,{onClick:()=>alert(`
              This score is computed as:


            `),children:"?"})]})})}),s.jsx(n,{xs:12,sm:6,md:3,children:s.jsx(c,{title:"Windows Latency Performance Score.",total:a,color:"primary",icon:s.jsxs("div",{children:[s.jsx("img",{alt:"icon",src:"/netperf/dist/assets/icons/glass/windows.png"}),s.jsx(u,{onClick:()=>alert(`
                  This score is computed as:


                `),children:"?"})]})})}),s.jsx(n,{xs:12,sm:6,md:3,children:s.jsx(c,{title:"Linux Latency Performance Score.",total:h,color:"primary",icon:s.jsxs("div",{children:[s.jsx("img",{alt:"icon",src:"/netperf/dist/assets/icons/glass/Ubuntu-Logo.png"}),s.jsx(u,{onClick:()=>alert(`
              This score is computed as:


            `),children:"?"})]})})}),s.jsx(n,{xs:12,md:6,lg:6,children:s.jsx(y,{title:"Throughput Comparison (GB / s)",subheader:`Tested using ${j}, ${S}`,chart:{labels:["Windows Download","Windows Upload","Linux Upload","Linux Download"],series:[{name:"TCP",type:"column",fill:"solid",data:[g,m,0,0]},{name:"QUIC",type:"column",fill:"solid",data:[w,e,0,0]}]}})}),s.jsx(n,{xs:12,md:6,lg:6,children:s.jsx(y,{title:"Latency Comparison (nanoseconds)",subheader:"Tested using Windows 11 build 22000.282, Linux Ubuntu 20.04.3 LTS",chart:{labels:["Windows + OpenSSL","Windows + Schannel","Linux + OpenSSL"],series:[{name:"TCP",type:"column",fill:"solid",data:[0,0,0]},{name:"QUIC",type:"column",fill:"solid",data:[0,0,0]}]}})})]})]})}function B(){return s.jsxs(s.Fragment,{children:[s.jsx(L,{children:s.jsx("title",{children:" Netperf "})}),s.jsx(k,{})]})}export{B as default};
