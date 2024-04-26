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

import FullLatCurve from './full-lat-curve';

let isMouseDown = false;

document.addEventListener('mousedown', function () {
  isMouseDown = true;
});

document.addEventListener('mouseup', function () {
  isMouseDown = false;
});

// ----------------------------------------------------------------------

export default function LatencyPage() {
  const URL = "https://raw.githubusercontent.com/microsoft/netperf/deploy/historical_latency_page.json";
  const { data } = useFetchData(URL);

  const [env, setEnv] = useState('azure');

  const [windowsOs, setWindowsOs] = useState('windows-2022-x64')

  const [linuxOs, setLinuxOs] = useState('ubuntu-20.04-x64')

  const [testType, setTestType] = useState('rps-up-512-down-4000')

  const [commitIndex, setCommitIndex] = useState(0);

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

  const handleChangePercentile = (event) => {
    setPercentile(event.target.value);
  };

  const handleChangeCommit = (event) => {
    setCommitIndex(event.target.value);
  }

  let mode1View = <div />
  let fullLatCurve = <div />

  let rep = []
  let linuxRep = []
  let indices = []
  let tcpiocp = []
  let quiciocp = []
  let tcpepoll = []
  let quicepoll = []
  let quicxdp = []
  let quicwsk = []

  if (data) {
    // TODO: Should we find the max of windows / linux run and use that as our baseline?
    rep = data[`${windowsOs}-${env}-iocp-schannel`][`${testType}-tcp`]['data'].slice().reverse();
    linuxRep = data[`${linuxOs}-${env}-epoll-openssl`][`${testType}-tcp`]['data'].slice().reverse();
    indices = Array.from({ length: Math.max(rep.length, linuxRep.length) }, (_, i) => i);
    indices.reverse();

    tcpiocp = data[`${windowsOs}-${env}-iocp-schannel`][`${testType}-tcp`]['data'].slice().reverse();
    quiciocp = data[`${windowsOs}-${env}-iocp-schannel`][`${testType}-quic`]['data'].slice().reverse();
    tcpepoll = data[`${linuxOs}-${env}-epoll-openssl`][`${testType}-tcp`]['data'].slice().reverse();
    quicepoll = data[`${linuxOs}-${env}-epoll-openssl`][`${testType}-quic`]['data'].slice().reverse();
    quicxdp = data[`${windowsOs}-${env}-xdp-schannel`][`${testType}-quic`]['data'].slice().reverse();
    quicwsk = data[`${windowsOs}-${env}-wsk-schannel`][`${testType}-quic`]['data'].slice().reverse();

    mode1View =
      <GraphView title={`Detailed Latency`}
        subheader={`Tested using ${windowsOs}, ${linuxOs}, taking the min of P0 of 3 runs. `}
        labels={indices}
        map={(index) => {
          if (isMouseDown) {
            window.location.href = `https://github.com/microsoft/msquic/commit/${rep[index][0]}`
          }
          return `<div style = "margin: 10px">

         <p> <b> Build date: </b> ${rep[index][3]} </p>
         <p> <b> Specific Windows / Linux OS versions this test ran on: </b> ${rep[index][2]},  ${linuxRep[index][2]} </p>
         <p> <b> Commit hash: </b> <a href="google.com"> ${rep[index][0]} </a> </p>

         <p> <b> TCP + iocp: </b> ${tcpiocp[index] && tcpiocp[index][5 + percentile]}, </p>
         <p> <b> QUIC + iocp: </b> ${quiciocp[index] && quiciocp[index][5 + percentile]}, </p>
         <p> <b> TCP + epoll: </b> ${tcpepoll[index] && tcpepoll[index][5 + percentile]}, </p>
         <p> <b> QUIC + epoll: </b> ${quicepoll[index] && quicepoll[index][5 + percentile]}, <b> QUIC + winXDP: </b> ${quicxdp[index] && quicxdp[index][5 + percentile]}, <b> QUIC + wsk: </b> ${quicwsk[index] && quicwsk[index][5 + percentile]} </p>
      </div>`
        }}
        series={[
          {
            name: 'TCP + iocp',
            type: 'line',
            fill: 'solid',
            data: tcpiocp.map((x) => x[5 + percentile]),
          },
          {
            name: 'QUIC + iocp',
            type: 'line',
            fill: 'solid',
            data: quiciocp.map((x) => x[5 + percentile]),
          },
          {
            name: 'TCP + epoll',
            type: 'line',
            fill: 'solid',
            data: tcpepoll.map((x) => x[5 + percentile]),
          },
          {
            name: 'QUIC + epoll',
            type: 'line',
            fill: 'solid',
            data: quicepoll.map((x) => x[5 + percentile]),
          },
          {
            name: 'QUIC + winXDP',
            type: 'line',
            fill: 'solid',
            data: quicxdp.map((x) => x[5 + percentile]),
          },
          {
            name: 'QUIC + wsk',
            type: 'line',
            fill: 'solid',
            data: quicwsk.map((x) => x[5 + percentile]),
          },
        ]}

        options = {{
          xaxis: {
            tickplacement: 'on',
          },
          markers: {
            size: 5,
          }
        }}

        />
  }

  const handleChange = (event) => {
    setEnv(event.target.value);
  };

  const handleChangeWindowsOs = (event) => {
    setWindowsOs(event.target.value);
  }

  const handleChangeLinuxOs = (event) => {
    setLinuxOs(event.target.value);
  }

  const handleChangeTestType = (event) => {
    setTestType(event.target.value);
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
        <div style={{ display: 'flex' }}>
          <Box sx={{}}>
            <FormControl>
              <InputLabel id="demo-simple-select-label">Context</InputLabel>
              <Select
                labelId="demo-simple-select-label"
                id="demo-simple-select"
                value={env}
                label="Context"
                onChange={handleChange}
                defaultValue={0}
              >
                <MenuItem value='azure'>azure</MenuItem>
                {windowsOs !== 'windows-2025-x64' && <MenuItem value='lab'>lab</MenuItem>}
              </Select>
            </FormControl>
          </Box>
          {/* <br /> */}
          <Box sx={{ minWidth: 120, marginLeft: '10px' }}>
            <FormControl>
              <InputLabel id="demo-simple-select-label">Windows Environment</InputLabel>
              <Select
                labelId="demo-simple-select-label"
                id="demo-simple-select"
                value={windowsOs}
                label="Windows Environment"
                onChange={handleChangeWindowsOs}
                defaultValue={0}
              >
                <MenuItem value='windows-2022-x64'>windows-2022-x64</MenuItem>
                {env === 'azure' && <MenuItem value='windows-2025-x64'>windows-2025-x64</MenuItem>}
              </Select>
            </FormControl>
          </Box>
          {/* <br /> */}
          <Box sx={{ minWidth: 120, marginLeft: '10px' }}>
            <FormControl>
              <InputLabel id="demo-simple-select-label">Linux Environment</InputLabel>
              <Select
                labelId="demo-simple-select-label"
                id="demo-simple-select"
                value={linuxOs}
                label="Linux Environment"
                onChange={handleChangeLinuxOs}
                defaultValue={0}
              >
                <MenuItem value='ubuntu-20.04-x64'>ubuntu-20.04-x64</MenuItem>
              </Select>
            </FormControl>
          </Box>
          <Box sx={{ minWidth: 120, marginLeft: '10px' }}>
            <FormControl>
              <InputLabel id="demo-simple-select-label">Test type</InputLabel>
              <Select
                labelId="demo-simple-select-label"
                id="demo-simple-select"
                value={testType}
                label="Upload or download"
                onChange={handleChangeTestType}
                defaultValue={0}
              >
                <MenuItem value={'rps-up-512-down-4000'}>512 Kb upload, 4000 Kb download</MenuItem>
              </Select>
            </FormControl>
          </Box>
          <Box sx={{ minWidth: 120, marginLeft: '10px' }}>
            <FormControl fullWidth>
              <InputLabel id="demo-simple-select-label">Percentile</InputLabel>
              <Select
                labelId="demo-simple-select-label"
                id="demo-simple-select"
                value={percentile}
                label="Percentile"
                onChange={handleChangePercentile}
                defaultValue={0}
              >
                {supportedPercentiles.map((val, idx) => <MenuItem value={idx}>{val}</MenuItem>)}
              </Select>
            </FormControl>
          </Box>
        </div>
        <br />

        <Grid container spacing={3}>
          {mode1View}
        </Grid>
        <Box sx={{ minWidth: 120, margin: '10px' }}>
          <FormControl fullWidth>
            <InputLabel id="demo-simple-select-label">Full Latency Curve Commit</InputLabel>
            <Select
              labelId="demo-simple-select-label"
              id="demo-simple-select"
              value={commitIndex}
              label="Full Latency Curve Commit"
              onChange={handleChangeCommit}
              defaultValue={0}
            >
              {rep.slice().reverse().map((val, idx) => <MenuItem value={idx}>Commit {idx}: {val[0]}</MenuItem>)}
            </Select>
          </FormControl>
        </Box>
        <Grid container spacing={3}>
          < FullLatCurve
            tcpiocp={tcpiocp}
            quiciocp={quiciocp}
            tcpepoll={tcpepoll}
            quicepoll={quicepoll}
            quicxdp={quicxdp}
            quicwsk={quicwsk}
            commitIndex={commitIndex}
          />
        </Grid>
      </Container>
    </>
  );
}

