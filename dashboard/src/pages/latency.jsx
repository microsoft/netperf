/* eslint-disable */

import { Helmet } from 'react-helmet-async';
import { useState } from 'react';
import Grid from '@mui/material/Unstable_Grid2';
import Container from '@mui/material/Container';
import Typography from '@mui/material/Typography';

import { GraphView } from 'src/sections/overview/graphing';
import useFetchData from 'src/hooks/use-fetch-data';

import Box from '@mui/material/Box';
import InputLabel from '@mui/material/InputLabel';
import MenuItem from '@mui/material/MenuItem';
import FormControl from '@mui/material/FormControl';
import Select from '@mui/material/Select';

let isMouseDown = false;

document.addEventListener('mousedown', function() {
    isMouseDown = true;
});

document.addEventListener('mouseup', function() {
    isMouseDown = false;
});

// ----------------------------------------------------------------------

export default function LatencyPage() {
  const URL = "https://raw.githubusercontent.com/microsoft/netperf/deploy/detailed_rps_and_latency_page.json";
  const { data } = useFetchData(URL);
  const supportedPercentiles = [
    "50th percentile",
    "90th percentile",
    "99th percentile",
    "99.9th percentile",
    "99.99th percentile",
    "99.999th percentile",
    "99.9999th percentile",
  ]
  const [percentile, setPercentile] = useState(0);

  const handleChange = (event) => {
    setPercentile(event.target.value);
  };

  let graphView = <div />
  if (data) {
    const indices = []
    for (let i = 0; i < data["linuxTcp"]["data"].length; i++) {
      indices.push(i + 1)
    }
    graphView = <GraphView title="Latency - Measured in Microseconds"
    subheader='Tested using Windows Server 2022, Linux Ubuntu 20.04.3 LTS'
    labels={indices}
    map={(index) => {
      if (isMouseDown) {
        window.location.href = `https://github.com/microsoft/msquic/commit/${data["linuxTcp"]["data"][index][2]}`
      }
      return `<div style = "margin: 10px">

         <p> <b> Build date: </b> ${data["linuxTcp"]["data"][index][1]} </p>
         <p> <b> Commit hash: </b> <a href="google.com"> ${data["linuxTcp"]["data"][index][2]} </a> </p>

         <p> <b> Linux TCP: </b> ${data["linuxTcp"]["data"][index][percentile + 3]} </p>
         <p> <b> Windows TCP: </b> ${data["windowsTcp"]["data"][index][percentile + 3]} </p>
         <p> <b> Linux QUIC: </b> ${data["linuxQuic"]["data"][index][percentile + 3]} </p>
         <p> <b> Windows QUIC: </b> ${data["windowsQuic"]["data"][index][percentile + 3]} </p>

      </div>`
    }}
    series={[
      {
        name: 'Linux + TCP',
        type: 'line',
        fill: 'solid',
        data: data["linuxTcp"]["data"].reverse().map((x) => x[percentile + 3]),

      },
      {
        name: 'Windows + TCP',
        type: 'line',
        fill: 'solid',
        data: data["windowsTcp"]["data"].reverse().map((x) => x[percentile + 3]),
      },
      {
        name: 'Linux + QUIC',
        type: 'line',
        fill: 'solid',
        data: data["linuxQuic"]["data"].reverse().map((x) => x[percentile + 3]),
      },
      {
        name: 'Windows + QUIC',
        type: 'line',
        fill: 'solid',
        data: data["windowsQuic"]["data"].reverse().map((x) => x[percentile + 3]),
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
          Detailed Latency
        </Typography>
        <Grid container spacing={3}>

        <Box sx={{ minWidth: 120 }}>
        <FormControl fullWidth>
          <InputLabel id="demo-simple-select-label">Percentile</InputLabel>
          <Select
            labelId="demo-simple-select-label"
            id="demo-simple-select"
            value={percentile}
            label="Percentile"
            onChange={handleChange}
            defaultValue={0}
          >
            {supportedPercentiles.map((val, idx) => <MenuItem value={idx}>{val}</MenuItem>)}
          </Select>
        </FormControl>
      </Box>
      {/* <br />
      <br />
      <p style={{margin: "10px"}}>{supportedPercentiles[percentile]}</p> */}
          {graphView}
        </Grid>
      </Container>
    </>
  );
}
