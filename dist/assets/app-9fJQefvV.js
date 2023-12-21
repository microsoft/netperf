import{r as x,j as t,S as C,B as E,T as b,P as c,a as f,W as Q}from"./index-PmougpPJ.js";import{A as P}from"./app-website-visits--n73KPD5.js";import{f as I}from"./format-number-IfcmQZGb.js";import{C as N}from"./Card-rD5HN412.js";import{C as O}from"./Container-pU06vF9A.js";import{G as d}from"./Grid2-jdwU-BoB.js";import"./isMuiElement-Sndw__DD.js";function k(i){const[s,n]=x.useState(null),[o,l]=x.useState(!0),[a,h]=x.useState(null);return x.useEffect(()=>{fetch(i).then(r=>{if(!r.ok)throw new Error("Network response was not ok");return r.json()}).then(r=>{n(r),l(!1)}).catch(r=>{h(r),l(!1)})},[i]),{data:s,isLoading:o,error:a}}function g({title:i,total:s,icon:n,color:o="primary",sx:l,...a}){return t.jsxs(N,{component:C,spacing:3,direction:"row",sx:{px:3,py:5,borderRadius:2,...l},...a,children:[n&&t.jsx(E,{sx:{width:64,height:64},children:n}),t.jsxs(C,{spacing:.5,children:[t.jsx(b,{variant:"h4",children:I(s)}),t.jsx(b,{variant:"subtitle2",sx:{color:"text.disabled"},children:i})]})]})}g.propTypes={color:c.string,icon:c.oneOfType([c.element,c.string]),sx:c.object,title:c.string,total:c.number};function U(i,s,n,o){return(i*n+s*o)/1e4}function v(i){const s=[.05,.1,.2,.3,.1,.1,.1,.05];let n=1;for(let o=0;o<i.length;o+=1)n+=s[o]*i[o];return 1/n*1e5}function A(){const i=k("https://raw.githubusercontent.com/microsoft/netperf/deploy/json-test-results-windows-windows-2022-x64-schannel.json"),s=k("https://raw.githubusercontent.com/microsoft/netperf/deploy/json-test-results-linux-ubuntu-20.04-x64-openssl.json");let n=0,o=0,l=0,a=0,h=1,r=1,j=1,L=1,T=1,S=1,y=1,W=1,u=[0,0,0,0,0,0,0,0],w=[0,0,0,0,0,0,0,0],p=[0,0,0,0,0,0,0,0],m=[0,0,0,0,0,0,0,0];const _="Windows Server 2022",D="Linux Ubuntu 20.04 LTS";if(i.data&&s.data){for(const e of Object.keys(i.data))e.includes("download")&&e.includes("quic")&&(j=i.data[e]),e.includes("download")&&e.includes("tcp")&&(L=i.data[e]),e.includes("upload")&&e.includes("quic")&&(h=i.data[e]),e.includes("upload")&&e.includes("tcp")&&(r=i.data[e]),e.includes("rps")&&e.includes("quic")&&(u=i.data[e]),e.includes("rps")&&e.includes("tcp")&&(w=i.data[e]);for(const e of Object.keys(s.data))e.includes("download")&&e.includes("quic")&&(T=s.data[e]),e.includes("download")&&e.includes("tcp")&&(S=s.data[e]),e.includes("upload")&&e.includes("quic")&&(y=s.data[e]),e.includes("upload")&&e.includes("tcp")&&(W=s.data[e]),e.includes("rps")&&e.includes("quic")&&(p=s.data[e]),e.includes("rps")&&e.includes("tcp")&&(m=s.data[e]);n=U(j,h,.8,.2),o=U(T,y,.8,.2),l=v(u),a=v(p),console.log(l),console.log(a)}return t.jsxs(O,{maxWidth:"xl",children:[t.jsx(b,{variant:"h3",sx:{mb:5},children:"Network Performance Overview"}),t.jsxs(d,{container:!0,spacing:3,children:[t.jsx(d,{xs:12,sm:6,md:3,children:t.jsx(g,{title:"Windows Throughput Performance Score.",total:n,color:"primary",icon:t.jsxs("div",{children:[t.jsx("img",{alt:"icon",src:"/netperf/dist/assets/icons/glass/windows.png"}),t.jsx(f,{onClick:()=>alert(`
                This score is computed as:

                WINDOWS = download_speed * download_weight + upload_speed * upload_weight
                
                SCORE = WINDOWS / 10000,

                where download_weight = 0.8, upload_weight = 0.2

                Essentially, we weigh download speed more than upload speed, since most internet users
                are using download a lot more often than upload.
              `),children:"?"})]})})}),t.jsx(d,{xs:12,sm:6,md:3,children:t.jsx(g,{title:"Linux Throughput Performance Score.",total:o,color:"primary",icon:t.jsxs("div",{children:[t.jsx("img",{alt:"icon",src:"/netperf/dist/assets/icons/glass/Ubuntu-Logo.png"}),t.jsx(f,{onClick:()=>alert(`
                This score is computed as:

                LINUX = download_speed * download_weight + upload_speed * upload_weight
                
                SCORE = LINUX / 10000,

                where download_weight = 0.8, upload_weight = 0.2

                Essentially, we weigh download speed more than upload speed, since most internet users
                are using download a lot more often than upload.

            `),children:"?"})]})})}),t.jsx(d,{xs:12,sm:6,md:3,children:t.jsx(g,{title:"Windows Latency Performance Score.",total:l,color:"primary",icon:t.jsxs("div",{children:[t.jsx("img",{alt:"icon",src:"/netperf/dist/assets/icons/glass/windows.png"}),t.jsx(f,{onClick:()=>alert(`
                  This score is computed as:
                  
                  We give a weighting to how important each percentile is:

                  0th percentile, 50th percentile, 90th percentile, 99th percentile, 99.99th percentile, 99.999th percentile, 99.9999th percentile
                  
                  The weights we used are weightings = [0.05, 0.1, 0.2, 0.3, 0.1, 0.1, 0.1, 0.05].

                  We think its important that in the 90th - 99.999th percentiles, we optimize it the most, since most
                  power users (Azure customers) will experience these latencies. 

                  Therefore, we give less weighting to the perfect case (0th percentile). 
                `),children:"?"})]})})}),t.jsx(d,{xs:12,sm:6,md:3,children:t.jsx(g,{title:"Linux Latency Performance Score.",total:a,color:"primary",icon:t.jsxs("div",{children:[t.jsx("img",{alt:"icon",src:"/netperf/dist/assets/icons/glass/Ubuntu-Logo.png"}),t.jsx(f,{onClick:()=>alert(`
              This score is computed as:
              
              This score is computed as:
                  
              We give a weighting to how important each percentile is:

              0th percentile, 50th percentile, 90th percentile, 99th percentile, 99.99th percentile, 99.999th percentile, 99.9999th percentile
              
              The weights we used are weightings = [0.05, 0.1, 0.2, 0.3, 0.1, 0.1, 0.1, 0.05].

              We think its important that in the 90th - 99.999th percentiles, we optimize it the most, since most
              power users (Azure customers) will experience these latencies. 

              Therefore, we give less weighting to the perfect case (0th percentile). 

            `),children:"?"})]})})}),t.jsx(d,{xs:12,md:6,lg:6,children:t.jsx(P,{title:"Throughput Comparison (kbps), higher the better.",subheader:`Tested using ${_}, ${D}`,chart:{labels:["Windows Download","Windows Upload","Linux Download","Linux Upload"],series:[{name:"TCP",type:"column",fill:"solid",data:[L,r,S,W]},{name:"QUIC",type:"column",fill:"solid",data:[j,h,T,y]}]}})}),t.jsx(d,{xs:12,md:6,lg:6,children:t.jsx(P,{title:"Latency Comparison (ms), lower the better.",subheader:"Tested using Windows 11 build 22000.282, Linux Ubuntu 20.04.3 LTS",chart:{labels:["Windows QUIC","Windows TCP","Linux QUIC","Linux TCP"],series:[{name:"50th percentile",type:"column",fill:"solid",data:[u[1],w[1],p[1],m[1]]},{name:"90th percentile",type:"column",fill:"solid",data:[u[2],w[2],p[2],m[2]]},{name:"99th percentile",type:"column",fill:"solid",data:[u[3],w[3],p[3],m[3]]},{name:"99.99th percentile",type:"column",fill:"solid",data:[u[4],w[4],p[4],m[4]]}]}})})]})]})}function X(){return t.jsxs(t.Fragment,{children:[t.jsx(Q,{children:t.jsx("title",{children:" Netperf "})}),t.jsx(A,{})]})}export{X as default};
