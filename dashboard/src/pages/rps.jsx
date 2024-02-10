/* eslint-disable */

import { Helmet } from 'react-helmet-async';
import { useState } from 'react';
import Grid from '@mui/material/Unstable_Grid2';
import Container from '@mui/material/Container';
import Typography from '@mui/material/Typography';

import { GraphView } from 'src/sections/overview/graphing';
import useFetchData from 'src/hooks/use-fetch-data';
let isMouseDown = false;

document.addEventListener('mousedown', function() {
    isMouseDown = true;
});

document.addEventListener('mouseup', function() {
    isMouseDown = false;
});

// ----------------------------------------------------------------------

export default function RpsPage() {
  const URL = "https://raw.githubusercontent.com/microsoft/netperf/deploy/detailed_rps_and_latency_page.json";
  const { data } = useFetchData(URL);

  let graphView = <div />
  if (data) {
    const indices = []
    for (let i = 0; i < data["linuxTcp"]["data"].length; i++) {
      indices.push(i + 1)
    }
    graphView = <GraphView title="Requests Per Second - Max out of 3 runs"
    subheader='Tested using Windows Server 2022, Linux Ubuntu 20.04.3 LTS'
    labels={indices}
    map={(index) => {
      if (isMouseDown) {
        window.location.href = `https://github.com/microsoft/msquic/commit/${data["linuxTcp"]["data"][index][2]}`
      }
      return `<div style = "margin: 10px">

         <p> <b> Build date: </b> ${data["linuxTcp"]["data"][index][1]} </p>
         <p> <b> Commit hash: </b> <a href="google.com"> ${data["linuxTcp"]["data"][index][2]} </a> </p>

         <p> <b> Linux TCP: </b> ${data["linuxTcp"]["data"][index][0]} </p>
         <p> <b> Windows TCP: </b> ${data["windowsTcp"]["data"][index][0]} </p>
         <p> <b> Linux QUIC: </b> ${data["linuxQuic"]["data"][index][0]} </p>
         <p> <b> Windows QUIC: </b> ${data["windowsQuic"]["data"][index][0]} </p>

      </div>`
    }}
    series={[
      {
        name: 'Linux + TCP',
        type: 'line',
        fill: 'solid',
        data: data["linuxTcp"]["data"].reverse().map((x) => x[0]),

      },
      {
        name: 'Windows + TCP',
        type: 'line',
        fill: 'solid',
        data: data["windowsTcp"]["data"].reverse().map((x) => x[0]),
      },
      {
        name: 'Linux + QUIC',
        type: 'line',
        fill: 'solid',
        data: data["linuxQuic"]["data"].reverse().map((x) => x[0]),
      },
      {
        name: 'Windows + QUIC',
        type: 'line',
        fill: 'solid',
        data: data["windowsQuic"]["data"].reverse().map((x) => x[0]),
      },
    ]}
  />

  }

  return (
    <>
      <Helmet>
        <title> Netperf </title>
      </Helmet>


      <Container maxWidth="xl">
        <Typography variant="h3" sx={{ mb: 5 }}>
          Detailed Requests Per Second
        </Typography>
        <Grid container spacing={3}>
      {/* <br />
      <br />
      <p style={{margin: "10px"}}>{supportedPercentiles[percentile]}</p> */}
          {graphView}
        </Grid>
      </Container>
    </>
  );
}
