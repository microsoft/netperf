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
import accessData from '../utils/common.js'

let isMouseDown = false;

document.addEventListener('mousedown', function() {
    isMouseDown = true;
});

document.addEventListener('mouseup', function() {
    isMouseDown = false;
});


export default function ThroughputPage() {

  const URL = "https://raw.githubusercontent.com/microsoft/netperf/deploy/historical_throughput_page.json";
  const { data } = useFetchData(URL);

  let uploadThroughput = <div />

  const [env, setEnv] = useState('azure');

  const [windowsOs, setWindowsOs] = useState('windows-2022-x64')

  const [linuxOs, setLinuxOs] = useState('ubuntu-24.04-x64')
  let OLD_LINUX_OS = 'ubuntu-20.04-x64'

  const [testType, setTestType] = useState('up')

  if (data) {
    let windowsRepresentative = accessData(`${windowsOs}-${env}-iocp-schannel`, data, `scenario-${testType}load-tcp`, `tput-${testType}-tcp`);
    let linuxRepresentative = accessData(`${linuxOs}-${env}-epoll-quictls`, data, `scenario-${testType}load-tcp`, `tput-${testType}-tcp`);
    let tcpepoll = accessData(`${linuxOs}-${env}-epoll-quictls`, data, `scenario-${testType}load-tcp`, `tput-${testType}-tcp`);
    let quicepoll = accessData(`${linuxOs}-${env}-epoll-quictls`, data, `scenario-${testType}load-quic`, `tput-${testType}-quic`);
    if (linuxRepresentative.length == 0 || quicepoll.length == 0 || tcpepoll.length == 0) {
      linuxRepresentative = accessData(`${OLD_LINUX_OS}-${env}-epoll-openssl`, data, `scenario-${testType}load-tcp`, `tput-${testType}-tcp`);
      tcpepoll = accessData(`${OLD_LINUX_OS}-${env}-epoll-openssl`, data, `scenario-${testType}load-tcp`, `tput-${testType}-tcp`);
      quicepoll = accessData(`${OLD_LINUX_OS}-${env}-epoll-openssl`, data, `scenario-${testType}load-quic`, `tput-${testType}-quic`);
    }


    const tcpiocp = accessData(`${windowsOs}-${env}-iocp-schannel`, data, `scenario-${testType}load-tcp`, `tput-${testType}-tcp`);
    const quiciocp = accessData(`${windowsOs}-${env}-iocp-schannel`, data, `scenario-${testType}load-quic`, `tput-${testType}-quic`);


    const quicxdp = accessData(`${windowsOs}-${env}-xdp-schannel`, data, `scenario-${testType}load-quic`, `tput-${testType}-quic`);
    const quicwsk = accessData(`${windowsOs}-${env}-wsk-schannel`, data, `scenario-${testType}load-quic`, `tput-${testType}-quic`);


    while (windowsRepresentative.length > linuxRepresentative.length) {
      windowsRepresentative.shift();
      tcpiocp.shift();
      quiciocp.shift();
      quicxdp.shift();
      quicwsk.shift();
    }
    let indices = Array.from({length: Math.max(windowsRepresentative.length, linuxRepresentative.length)}, (_, i) => i);
    indices.reverse();


    const TCPIOCP = tcpiocp.map(x => x[0]);
    const QUICIOCP = quiciocp.map(x => x[0]);
    const TCPEPOLL = tcpepoll.map(x => x[0]);
    const QUICEPOLL = quicepoll.map(x => x[0]);
    const QUICXDP = quicxdp.map(x => x[0]);
    const QUICWSK = quicwsk.map(x => x[0]);


    uploadThroughput =
      <GraphView title={`${testType === 'up' ? 'Upload' : 'Download'} Throughput`}
        subheader={`Tested using ${windowsOs}, ${linuxOs}, taking the max of 3 runs. `}
        labels={indices}
        map={(index) => {
          if (isMouseDown) {
            window.location.href = `https://github.com/microsoft/msquic/commit/${windowsRepresentative[index][1]}`
          }
          return `<div style = "margin: 10px">
            <p> <b> Build date: </b> ${windowsRepresentative[index][3]} </p>
            <p> <b> Specific Windows OS version this test ran on: </b> ${windowsRepresentative[index][2]} </p>
            <p> <b> Specific Linux OS version this test ran on: </b> ${linuxRepresentative[index][2]} </p>
            <p> <b> Commit hash: </b> <a href="google.com"> ${windowsRepresentative[index][1]} </a> </p>
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
          Historical throughput
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
              <MenuItem value='ubuntu-24.04-x64'>ubuntu-24.04-x64</MenuItem>
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
              <MenuItem value={'up'}>Upload - 1 connection, 12 seconds per run</MenuItem>
              <MenuItem value={'down'}>Download - 1 connection, 12 seconds per run</MenuItem>
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
