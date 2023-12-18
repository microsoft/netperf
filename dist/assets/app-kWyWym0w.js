import{r as x,j as o,S as b,B as C,T as g,P as e,a as m,W}from"./index-5poD3ZKP.js";import{A as _}from"./app-website-visits-ZyAQV-eo.js";import{f as P}from"./format-number-x7gCONpi.js";import{C as U}from"./Card-GXO6Ut1f.js";import{C as k}from"./Container-h6E1Nvoh.js";import{G as i}from"./Grid2-ZtnTgQVn.js";import"./isMuiElement-oLM_lVGN.js";function v(t){const[c,r]=x.useState(null),[l,n]=x.useState(!0),[a,w]=x.useState(null);return x.useEffect(()=>{fetch(t).then(s=>{if(!s.ok)throw new Error("Network response was not ok");return s.json()}).then(s=>{r(s),n(!1)}).catch(s=>{w(s),n(!1)})},[t]),{data:c,isLoading:l,error:a}}function d({title:t,total:c,icon:r,color:l="primary",sx:n,...a}){return o.jsxs(U,{component:b,spacing:3,direction:"row",sx:{px:3,py:5,borderRadius:2,...n},...a,children:[r&&o.jsx(C,{sx:{width:64,height:64},children:r}),o.jsxs(b,{spacing:.5,children:[o.jsx(g,{variant:"h4",children:P(c)}),o.jsx(g,{variant:"subtitle2",sx:{color:"text.disabled"},children:t})]})]})}d.propTypes={color:e.string,icon:e.oneOfType([e.element,e.string]),sx:e.object,title:e.string,total:e.number};function D(){const{data:t,isLoading:c,error:r}=v("https://raw.githubusercontent.com/microsoft/netperf/deploy/landing_page.json");let l=0,n=0;const a=0,w=0;let s=0,f=0,u=0,j=0,p=0,T=0,h=0,y=0,L="",S="";return t&&(L=t.windows.type,S=t.linux.type,u=t.windows.download_throughput_quic,j=t.windows.download_throughput_tcp,s=t.windows.upload_throughput_quic,f=t.windows.upload_throughput_tcp,p=t.linux.download_throughput_quic,T=t.linux.download_throughput_tcp,h=t.linux.upload_throughput_quic,y=t.linux.upload_throughput_tcp,l=(u+s)/(p+h)*100,n=(p+h)/(u+s)*100),o.jsxs(k,{maxWidth:"xl",children:[o.jsx(g,{variant:"h3",sx:{mb:5},children:"Network Performance Overview"}),o.jsx("p",{children:"Data as of 10/10/2023 (Latest Commit)"}),o.jsxs(i,{container:!0,spacing:3,children:[o.jsx(i,{xs:12,sm:6,md:3,children:o.jsx(d,{title:"Windows Throughput Performance Score.",total:l,color:"primary",icon:o.jsxs("div",{children:[o.jsx("img",{alt:"icon",src:"/netperf/dist/assets/icons/glass/windows.png"}),o.jsx(m,{onClick:()=>alert(`
                This score is computed as:

                X = Windows throughput download + upload
                Y = Linux throughput download + upload

                performance score = [X / Y] * 100.

                Essentially, proportionally,
                Windows Throughput
                in terms of Linux.
              `),children:"?"})]})})}),o.jsx(i,{xs:12,sm:6,md:3,children:o.jsx(d,{title:"Linux Throughput Performance Score.",total:n,color:"primary",icon:o.jsxs("div",{children:[o.jsx("img",{alt:"icon",src:"/netperf/dist/assets/icons/glass/Ubuntu-Logo.png"}),o.jsx(m,{onClick:()=>alert(`
                  This score is computed as:

                  X = Windows throughput download + upload
                  Y = Linux throughput download + upload

                  performance score = [Y / X] * 100.

                  Essentially, proportionally,
                  Linux Throughput
                  in terms of Windows.

            `),children:"?"})]})})}),o.jsx(i,{xs:12,sm:6,md:3,children:o.jsx(d,{title:"Windows Latency Performance Score.",total:a,color:"primary",icon:o.jsxs("div",{children:[o.jsx("img",{alt:"icon",src:"/netperf/dist/assets/icons/glass/windows.png"}),o.jsx(m,{onClick:()=>alert(`
                  This score is computed as:


                `),children:"?"})]})})}),o.jsx(i,{xs:12,sm:6,md:3,children:o.jsx(d,{title:"Linux Latency Performance Score.",total:w,color:"primary",icon:o.jsxs("div",{children:[o.jsx("img",{alt:"icon",src:"/netperf/dist/assets/icons/glass/Ubuntu-Logo.png"}),o.jsx(m,{onClick:()=>alert(`
              This score is computed as:


            `),children:"?"})]})})}),o.jsx(i,{xs:12,md:6,lg:6,children:o.jsx(_,{title:"Throughput Comparison (kbps)",subheader:`Tested using ${L}, ${S}`,chart:{labels:["Windows Download","Windows Upload","Linux Download","Linux Upload"],series:[{name:"TCP",type:"column",fill:"solid",data:[j,f,T,y]},{name:"QUIC",type:"column",fill:"solid",data:[u,s,p,h]}]}})}),o.jsx(i,{xs:12,md:6,lg:6,children:o.jsx(_,{title:"Latency Comparison (nanoseconds)",subheader:"Tested using Windows 11 build 22000.282, Linux Ubuntu 20.04.3 LTS",chart:{labels:["Windows + OpenSSL","Windows + Schannel","Linux + OpenSSL"],series:[{name:"TCP",type:"column",fill:"solid",data:[0,0,0]},{name:"QUIC",type:"column",fill:"solid",data:[0,0,0]}]}})})]})]})}function Y(){return o.jsxs(o.Fragment,{children:[o.jsx(W,{children:o.jsx("title",{children:" Netperf "})}),o.jsx(D,{})]})}export{Y as default};
