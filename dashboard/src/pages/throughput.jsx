/* eslint-disable */

import { Helmet } from 'react-helmet-async';
import Grid from '@mui/material/Unstable_Grid2';
import Container from '@mui/material/Container';
import Typography from '@mui/material/Typography';
import useFetchData from 'src/hooks/use-fetch-data';
import { GraphView } from 'src/sections/overview/graphing';

let isMouseDown = false;

document.addEventListener('mousedown', function() {
    isMouseDown = true;
});

document.addEventListener('mouseup', function() {
    isMouseDown = false;
});

// ----------------------------------------------------------------------

export default function ThroughputPage() {

  const URL = "https://raw.githubusercontent.com/microsoft/netperf/deploy/throughput.json";
  const { data } = useFetchData(URL);
  let uploadThroughput = <div />
  let downloadThroughput = <div />

  if (data) {
    const indices = []
    for (let i = 0; i < data["linuxTcpUploadThroughput"].length; i++) {
      indices.push(i + 1)
    }
    data["linuxTcpUploadThroughput"].reverse()
    uploadThroughput =
      <GraphView title="Upload Throughput"
    subheader='Tested using Windows Server 2022 (Client and Server). Linux Ubuntu 20.04.3 LTS (Client and Server). WIP, NOTE: each datapoint is the max of 3 runs.'
    labels={indices}
    map={(index) => {
      if (isMouseDown) {
        window.location.href = `https://github.com/microsoft/msquic/commit/${data["linuxTcpUploadThroughput"][index][2]}`
      }
      return `<div style = "margin: 10px">

          NOTE: still a WIP, data is the max of 3 runs.

         <p> <b> Build date: </b> ${data["linuxTcpUploadThroughput"][index][1]} </p>
         <p> <b> Commit hash: </b> <a href="google.com"> ${data["linuxTcpUploadThroughput"][index][2]} </a> </p>

         <p> <b> Linux TCP: </b> ${data["linuxTcpUploadThroughput"][index][0]} </p>
         <p> <b> Windows TCP: </b> ${data["windowsTcpUploadThroughput"][index][0]} </p>
         <p> <b> Linux QUIC: </b> ${data["linuxQuicUploadThroughput"][index][0]} </p>
         <p> <b> Windows QUIC: </b> ${data["windowsQuicUploadThroughput"][index][0]} </p>

      </div>`
    }}
    series={[
      {
        name: 'Linux + TCP',
        type: 'line',
        fill: 'solid',
        data: data["linuxTcpUploadThroughput"].map((x) => x[0])
      },
      {
        name: 'Windows + TCP',
        type: 'line',
        fill: 'solid',
        data: data["windowsTcpUploadThroughput"].map((x) => x[0]),
      },
      {
        name: 'Linux + QUIC',
        type: 'line',
        fill: 'solid',
        data: data["linuxQuicUploadThroughput"].map((x) => x[0]),
      },
      {
        name: 'Windows + QUIC',
        type: 'line',
        fill: 'solid',
        data: data["windowsQuicUploadThroughput"].map((x) => x[0]),
      },
    ]} />

    downloadThroughput =  <GraphView title="Download Throughput"
    subheader='Tested using Windows Server 2022 (Client and Server). Linux Ubuntu 20.04.3 LTS (Client and Server). WIP, NOTE: each datapoint is the max of 3 runs.'
    labels={indices}
    map={(index) => {
      if (isMouseDown) {
        window.location.href = `https://github.com/microsoft/msquic/commit/${data["linuxTcpDownloadThroughput"][index][2]}`
      }
      return `<div style = "margin: 10px">

          NOTE: still a WIP, data is the max of 3 runs.

         <p> <b> Build date: </b> ${data["linuxTcpDownloadThroughput"][index][1]} </p>
         <p> <b> Commit hash: </b> <a href="google.com"> ${data["linuxTcpDownloadThroughput"][index][2]} </a> </p>

         <p> <b> Linux TCP: </b> ${data["linuxTcpDownloadThroughput"][index][0]} </p>
         <p> <b> Windows TCP: </b> ${data["windowsTcpDownloadThroughput"][index][0]} </p>
         <p> <b> Linux QUIC: </b> ${data["linuxQuicDownloadThroughput"][index][0]} </p>
         <p> <b> Windows QUIC: </b> ${data["windowsQuicDownloadThroughput"][index][0]} </p>

      </div>`
    }}
    series={[
      {
        name: 'Linux + TCP',
        type: 'line',
        fill: 'solid',
        data: data["linuxTcpDownloadThroughput"].map((x) => x[0])
      },
      {
        name: 'Windows + TCP',
        type: 'line',
        fill: 'solid',
        data: data["windowsTcpDownloadThroughput"].map((x) => x[0]),
      },
      {
        name: 'Linux + QUIC',
        type: 'line',
        fill: 'solid',
        data: data["linuxQuicDownloadThroughput"].map((x) => x[0]),
      },
      {
        name: 'Windows + QUIC',
        type: 'line',
        fill: 'solid',
        data: data["windowsQuicDownloadThroughput"].map((x) => x[0]),
      },
    ]} />
  }

  return (
    <>
      <Helmet>
        <title> Netperf </title>
      </Helmet>

      <Container maxWidth="xl">
        <Typography variant="h3" sx={{ mb: 5 }}>
          Detailed Throughput
        </Typography>
        <Grid container spacing={3}>
          {uploadThroughput}
          {downloadThroughput}
        </Grid>
      </Container>
    </>
  );
}
