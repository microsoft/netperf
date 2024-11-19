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

function accessData(envStr, data, newKey, oldKey) {
  const HISTORY_SIZE = 20;
  if (!(envStr in data)) {
    alert(`Could not find ${envStr} in data`);
    console.error(`Could not find ${envStr} in data`);
    return [];
  }
  const envData = data[envStr];
  let outputData = [];
  if (oldKey in envData) {
    outputData = envData[oldKey]['data'].slice().reverse();
  } else {
    console.log("OLD KEY DOES NOT EXIST", oldKey);
  }
  if (newKey in envData) {
    outputData = outputData.concat(envData[newKey]['data'].slice().reverse());
  } else {
    console.log("NEW KEY DOES NOT EXIST", newKey);
  }
  while (outputData.length > HISTORY_SIZE) {
    outputData.shift();
  }
  return outputData;
}

export default function RpsPage() {

  const URL = "https://raw.githubusercontent.com/microsoft/netperf/deploy/historical_rps_page.json";
  const { data } = useFetchData(URL);
  let rpsCurve = <div />

  const [env, setEnv] = useState('azure');

  const [windowsOs, setWindowsOs] = useState('windows-2022-x64')

  const [linuxOs, setLinuxOs] = useState('ubuntu-20.04-x64')

  const [testType, setTestType] = useState('rps-up-512-down-4000')

  if (data) {
    // TODO: Should we find the max of windows / linux run and use that as our baseline?
    let rep = accessData(`${windowsOs}-${env}-iocp-schannel`, data, `rps-tcp`, `${testType}-tcp`);
    let linuxRep = accessData(`${linuxOs}-${env}-epoll-openssl`, data, `rps-tcp`, `${testType}-tcp`);
    let indices = Array.from({length: Math.max(rep.length, linuxRep.length)}, (_, i) => i);
    indices.reverse();

    const tcpiocp = accessData(`${windowsOs}-${env}-iocp-schannel`, data, `rps-tcp`, `${testType}-tcp`);
    const quiciocp = accessData(`${windowsOs}-${env}-iocp-schannel`, data, `rps-quic`, `${testType}-quic`);
    const tcpepoll = accessData(`${linuxOs}-${env}-epoll-openssl`, data, `rps-tcp`, `${testType}-tcp`);
    const quicepoll = accessData(`${linuxOs}-${env}-epoll-openssl`, data, `rps-quic`, `${testType}-quic`);
    const quicxdp = accessData(`${windowsOs}-${env}-xdp-schannel`, data, `rps-quic`, `${testType}-quic`);
    const quicwsk = accessData(`${windowsOs}-${env}-wsk-schannel`, data, `rps-quic`, `${testType}-quic`);

    const TCPIOCP = tcpiocp.map(x => x[0]);
    const QUICIOCP = quiciocp.map(x => x[0]);
    const TCPEPOLL = tcpepoll.map(x => x[0]);
    const QUICEPOLL = quicepoll.map(x => x[0]);
    const QUICXDP = quicxdp.map(x => x[0]);
    const QUICWSK = quicwsk.map(x => x[0]);

    rpsCurve =
      <GraphView title={`Requests Per Second Throughput`}
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
         <b> QUIC + wsk: </b> ${quicwsk[index] && quicwsk[index][0]} </p>
      </div>`
    }}
    series={[
      {
        name: 'TCP + iocp',
        type: 'line',
        fill: 'solid',
        data: TCPIOCP,
      },
      {
        name: 'QUIC + iocp',
        type: 'line',
        fill: 'solid',
        data: QUICIOCP,
      },
      {
        name: 'TCP + epoll',
        type: 'line',
        fill: 'solid',
        data: TCPEPOLL,
      },
      {
        name: 'QUIC + epoll',
        type: 'line',
        fill: 'solid',
        data: QUICEPOLL,
      },
      {
        name: 'QUIC + winXDP',
        type: 'line',
        fill: 'solid',
        data: QUICXDP,
      },
      {
        name: 'QUIC + wsk',
        type: 'line',
        fill: 'solid',
        data: QUICWSK,
      },
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
          Detailed Requests Per Second
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
              label="test type"
              onChange={handleChangeTestType}
              defaultValue={0}
            >
              <MenuItem value={'rps-up-512-down-4000'}>512 kb upload, 4000 kb download</MenuItem>
            </Select>
          </FormControl>
        </Box>
        </div>
        <br />

        <Grid container spacing={3}>
          {rpsCurve}
        </Grid>
      </Container>
    </>
  );
}
