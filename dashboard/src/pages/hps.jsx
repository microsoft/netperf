/* eslint-disable */

import { useState } from 'react';
import { Helmet } from 'react-helmet-async';
import Grid from '@mui/material/Unstable_Grid2';
import Container from '@mui/material/Container';
import Typography from '@mui/material/Typography';
import useFetchData from 'src/hooks/use-fetch-data';
import { GraphView } from 'src/sections/overview/graphing';


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

export default function HpsPage() {

  const URL = "https://raw.githubusercontent.com/microsoft/netperf/deploy/historical_hps_page.json";
  const { data } = useFetchData(URL);
  let uploadThroughput = <div />

  const [env, setEnv] = useState('azure');

  const [windowsOs, setWindowsOs] = useState('windows-2022-x64')

  const [linuxOs, setLinuxOs] = useState('ubuntu-20.04-x64')

  const [testType, setTestType] = useState('hps-conns-100')

  if (data) {
    // TODO: Should we find the max of windows / linux run and use that as our baseline?
    let rep = data[`${windowsOs}-${env}-iocp-schannel`][`${testType}-tcp`]['data'].slice().reverse();
    let linuxRep = data[`${linuxOs}-${env}-epoll-openssl`][`${testType}-tcp`]['data'].slice().reverse();
    let indices = Array.from({length: Math.max(rep.length, linuxRep.length)}, (_, i) => i);
    indices.reverse();
    const tcpiocp = data[`${windowsOs}-${env}-iocp-schannel`][`${testType}-tcp`]['data'].slice().reverse();
    const quiciocp = data[`${windowsOs}-${env}-iocp-schannel`][`${testType}-quic`]['data'].slice().reverse();
    const tcpepoll = data[`${linuxOs}-${env}-epoll-openssl`][`${testType}-tcp`]['data'].slice().reverse();
    const quicepoll = data[`${linuxOs}-${env}-epoll-openssl`][`${testType}-quic`]['data'].slice().reverse();
    const quicxdp = data[`${windowsOs}-${env}-xdp-schannel`][`${testType}-quic`]['data'].slice().reverse();
    // const quicwsk = data[`${windowsOs}-${env}-wsk-schannel`][`${testType}-quic`]['data'].slice().reverse();

    uploadThroughput =
      <GraphView title={`${testType === 'up' ? 'Upload' : 'Download'} Throughput`}
    subheader={`Tested using ${windowsOs}, ${linuxOs}, taking the max of 3 runs. `}
    labels={indices}
    map={(index) => {
      if (isMouseDown) {
        window.location.href = `https://github.com/microsoft/msquic/commit/${rep[index][1]}`
      }
      return `<div style = "margin: 10px">

         <p> <b> Build date: </b> ${rep[index][3]} </p>
         <p> <b> Specific Windows OS version this test ran on: </b> ${rep[index][2]} </p>
         <p> <b> Specific Linux OS version this test ran on: </b> ${linuxRep[index][2]} </p>
         <p> <b> Commit hash: </b> <a href="google.com"> ${rep[index][1]} </a> </p>

         <p> <b> TCP + iocp: </b> ${tcpiocp[index] && tcpiocp[index][0]}, </p>
         <p> <b> QUIC + iocp: </b> ${quiciocp[index] && quiciocp[index][0]} </p>
         <p> <b> TCP + epoll: </b> ${tcpepoll[index] && tcpepoll[index][0]} </p>
         <p> <b> QUIC + epoll: </b> ${quicepoll[index] && quicepoll[index][0]},
         <b> QUIC + winXDP: </b> ${quicxdp[index] && quicxdp[index][0]},


      </div>`
    }}
    series={[
      {
        name: 'TCP + iocp',
        type: 'line',
        fill: 'solid',
        data: tcpiocp.map((x) => x[0]),
      },
      {
        name: 'QUIC + iocp',
        type: 'line',
        fill: 'solid',
        data: quiciocp,
      },
      {
        name: 'TCP + epoll',
        type: 'line',
        fill: 'solid',
        data: tcpepoll,
      },
      {
        name: 'QUIC + epoll',
        type: 'line',
        fill: 'solid',
        data: quicepoll,
      },
      {
        name: 'QUIC + winXDP',
        type: 'line',
        fill: 'solid',
        data: quicxdp,
      },
      // {
      //   name: 'QUIC + wsk',
      //   type: 'line',
      //   fill: 'solid',
      //   data: quicwsk,
      // },

    ]}

    options={{
      markers: {
        size: 5
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
          Detailed Handshakes Per Second
        </Typography>
        <div style={{display: 'flex'}}>
        <Box sx={{ }}>
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
              { windowsOs !== 'windows-2025-x64' && <MenuItem value='lab'>lab</MenuItem> }
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
              { env === 'azure' && <MenuItem value='windows-2025-x64'>windows-2025-x64</MenuItem> }
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
              label="Test type"
              onChange={handleChangeTestType}
              defaultValue={0}
            >
              <MenuItem value={'hps-conns-100'}>100 Connections</MenuItem>
            </Select>
          </FormControl>
        </Box>
        </div>
        <br />

        <Grid container spacing={3}>
          {uploadThroughput}
        </Grid>
      </Container>
    </>
  );
}
