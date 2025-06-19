/* eslint-disable no-restricted-syntax */

import { useState } from 'react';

import Button from '@mui/material/Button';
import Container from '@mui/material/Container';
import Grid from '@mui/material/Unstable_Grid2';
import Typography from '@mui/material/Typography';


import Box from '@mui/material/Box';
import InputLabel from '@mui/material/InputLabel';
import MenuItem from '@mui/material/MenuItem';
import FormControl from '@mui/material/FormControl';
import Select from '@mui/material/Select';


import useFetchData from 'src/hooks/use-fetch-data';
import AppWebsiteVisits from '../app-website-visits';
import AppWidgetSummary from '../app-widget-summary';

import getLatestSkuInformation from '../../../utils/sku';


function throughputPerformance(download, upload, dweight, uweight) {
  return (download * dweight + upload * uweight) / 100000;
}

function latencyPerformance(latencies) {
  const weighting = [0.05, 0.1, 0.2, 0.3, 0.1, 0.1, 0.1, 0.05];
  let sum = 1.0;
  for (let i = 0; i < 8; i += 1) {
    sum += weighting[i] * latencies[i];
  }
  return (1 / sum) * 100000;
}

// getLatestSkuInformation("", "", {})

// ----------------------------------------------------------------------

export default function AppView() {
  const [env, setEnv] = useState('azure');

  const [windowsOs, setWindowsOs] = useState('windows-2022-x64')

  const [linuxOs, setLinuxOs] = useState('ubuntu-24.04-x64')

  const windows = useFetchData(
    `https://raw.githubusercontent.com/microsoft/netperf/deploy/json-test-results-${env}-${windowsOs}-schannel-iocp.json/json-test-results-${env}-${windowsOs}-schannel-iocp.json`
  );

  const linux = useFetchData(
    `https://raw.githubusercontent.com/microsoft/netperf/deploy/json-test-results-${env}-${linuxOs}-quictls-epoll.json/json-test-results-${env}-${linuxOs}-quictls-epoll.json`
  );

  const windowsXdp = useFetchData(
    `https://raw.githubusercontent.com/microsoft/netperf/deploy/json-test-results-${env}-${windowsOs}-schannel-xdp.json/json-test-results-${env}-${windowsOs}-schannel-xdp.json`
  );

  const windowsKernel = useFetchData(
    `https://raw.githubusercontent.com/microsoft/netperf/deploy/json-test-results-${env}-${windowsOs}-schannel-wsk.json/json-test-results-${env}-${windowsOs}-schannel-wsk.json`
  );

  let windowsPerfScore = 0;
  let linuxPerfScore = 0;

  let windowsPerfScoreLatency = 0;
  let linuxPerfScoreLatency = 0;

  let windowsPerfScoreRps = 0;
  let linuxPerfScoreRps = 0;

  let windowsPerfScoreHps = 0;
  let linuxPerfScoreHps = 0;

  let windowsUploadThroughputQuic = -1;
  let windowsUploadThroughputTcp = -1;
  let windowsDownloadThroughputQuic = -1;
  let windowsDownloadThroughputTcp = -1;

  let windowsXdpUploadThroughputQuic = -1;
  let windowsXdpDownloadThroughputQuic = -1;

  let windowsKernelUploadThroughputQuic = -1;
  let windowsKernelDownloadThroughputQuic = -1;

  let linuxDownloadThroughputQuic = -1;
  let linuxDownloadThroughputTcp = -1;
  let linuxUploadThroughputQuic = -1;
  let linuxUploadThroughputTcp = -1;

  let windowsHpsQuic = -1;
  let windowsHpsTcp = -1;
  let linuxHpsQuic = -1;
  let linuxHpsTcp = -1;
  let windowsXdpHpsQuic = -1;

  let windowsRpsQuic = -1;
  let windowsRpsTcp = -1;
  let linuxRpsQuic = -1;
  let linuxRpsTcp = -1;
  let windowsXdpRpsQuic = -1;
  let windowsKernelRpsQuic = 1;


  let windowsLatencyQuic = [-1, -1, -1, -1, -1, -1, -1, -1];
  let windowsLatencyTcp = [-1, -1, -1, -1, -1, -1, -1, -1];
  let linuxLatencyQuic = [-1, -1, -1, -1, -1, -1, -1, -1];
  let linuxLatencyTcp = [-1, -1, -1, -1, -1, -1, -1, -1];

  let windowsXdpLatencyQuic = [-1, -1, -1, -1, -1, -1, -1, -1];

  let windowsKernelLatencyQuic = [-1, -1, -1, -1, -1, -1, -1, -1];
  let commitHash = "";
  let windowsType = 'Windows Server 2022';
  let linuxType = 'Linux Ubuntu 24.04 LTS';

  function index(object, keys, defaultValue) {
    for (const key of keys) {
      if (object && key in object) {
        return object[key];
      }
    }
    return defaultValue;
  }

  function fetchRPS(data, stub) {
    // data shape: [ ...8 dummy latency points... RPS for run 1 ... RPS for run 2 ... RPS for run 3]
    if (!data) {
      return stub;
    }
    const offset = 9;
    let tot = 0;
    let n = 0;
    for (let i = offset; i <= data.length; i += offset) {
      tot += Number(data[i - 1]);
      n += 1;
    }
    if (n === 0) {
      return stub;
    }
    console.log("RPS", tot, n)
    return Math.floor(tot / n)
  }

  if (windows.data && linux.data && windowsXdp.data && windowsKernel.data) {
    commitHash = windows.data.commit;
    windowsType = `${windowsOs} ${windows.data.os_version}`
    linuxType = `${linuxOs} ${linux.data.os_version}`
    // Throughput
    windowsDownloadThroughputQuic = Math.max(...index(windows.data, ["download-quic", "tput-down-quic"], [-1]));
    windowsDownloadThroughputTcp = Math.max(...index(windows.data, ["download-tcp", "tput-down-tcp"], [-1]));
    windowsUploadThroughputQuic = Math.max(...index(windows.data, ["upload-quic", "tput-up-quic"], [-1]));
    windowsUploadThroughputTcp = Math.max(...index(windows.data, ["upload-tcp", "tput-up-tcp"], [-1]));
    linuxDownloadThroughputQuic = Math.max(...index(linux.data, ["download-quic", "tput-down-quic"], [-1]));
    linuxDownloadThroughputTcp = Math.max(...index(linux.data, ["download-tcp", "tput-down-tcp"], [-1]));
    linuxUploadThroughputQuic = Math.max(...index(linux.data, ["upload-quic", "tput-up-quic"], [-1]));
    linuxUploadThroughputTcp = Math.max(...index(linux.data, ["upload-tcp", "tput-up-tcp"], [-1]));
    windowsKernelDownloadThroughputQuic = Math.max(...index(windowsKernel.data, ["download-quic", "tput-down-quic"], [-1]));
    windowsKernelUploadThroughputQuic = Math.max(...index(windowsKernel.data, ["upload-quic", "tput-up-quic"], [-1]));
    windowsXdpDownloadThroughputQuic = Math.max(...index(windowsXdp.data, ["download-quic", "tput-down-quic"], [-1]));
    windowsXdpUploadThroughputQuic = Math.max(...index(windowsXdp.data, ["upload-quic", "tput-up-quic"], [-1]));

    console.log("WINDOWS XDP TPUT", windowsXdpUploadThroughputQuic)

    // Latency
    windowsLatencyQuic = index(windows.data, ["latency-quic", "rps-up-512-down-4000-quic"], windowsLatencyQuic);
    windowsLatencyTcp = index(windows.data, ["latency-tcp", "rps-up-512-down-4000-tcp"], windowsLatencyTcp);
    linuxLatencyQuic = index(linux.data, ["latency-quic", "rps-up-512-down-4000-quic"], linuxLatencyQuic);
    linuxLatencyTcp = index(linux.data, ["latency-tcp", "rps-up-512-down-4000-tcp"], linuxLatencyTcp);
    windowsXdpLatencyQuic = index(windowsXdp.data, ["latency-quic", "rps-up-512-down-4000-quic"], windowsXdpLatencyQuic);
    windowsKernelLatencyQuic = index(windowsKernel.data, ["latency-quic", "rps-up-512-down-4000-quic"], windowsKernelLatencyQuic);


    // Compute Scores
    windowsPerfScore = throughputPerformance(
      windowsDownloadThroughputQuic,
      windowsUploadThroughputQuic,
      0.8,
      0.2
    );
    linuxPerfScore = throughputPerformance(
      linuxDownloadThroughputQuic,
      linuxUploadThroughputQuic,
      0.8,
      0.2
    );
    windowsPerfScoreLatency = latencyPerformance(windowsLatencyQuic);
    linuxPerfScoreLatency = latencyPerformance(linuxLatencyQuic);

    // HPS
    windowsHpsQuic = Math.max(...index(windows.data, ["hps-quic", "hps-conns-100-quic"], [-1]));
    windowsHpsTcp = Math.max(...index(windows.data, ["hps-tcp", "hps-conns-100-tcp"], [-1]));
    linuxHpsQuic = Math.max(...index(linux.data, ["hps-quic", "hps-conns-100-quic"], [-1]));
    linuxHpsTcp = Math.max(...index(linux.data, ["hps-tcp", "hps-conns-100-tcp"], [-1]));
    windowsXdpHpsQuic = Math.max(...index(windowsXdp.data, ["hps-quic", "hps-conns-100-quic"], [-1]));

    // RPS
    windowsRpsQuic = fetchRPS(index(windows.data, ["rps-quic"], null), windowsLatencyQuic[windowsLatencyQuic.length - 1]);
    windowsRpsTcp = fetchRPS(index(windows.data, ["rps-tcp"], null), windowsLatencyTcp[windowsLatencyTcp.length - 1]);
    linuxRpsQuic = fetchRPS(index(linux.data, ["rps-quic"], null), linuxLatencyQuic[linuxLatencyQuic.length - 1]);
    linuxRpsTcp = fetchRPS(index(linux.data, ["rps-tcp"], null), linuxLatencyTcp[linuxLatencyTcp.length - 1]);
    windowsXdpRpsQuic = fetchRPS(index(windowsXdp.data, ["rps-quic"], null), windowsXdpLatencyQuic[windowsXdpLatencyQuic.length - 1]);
    windowsKernelRpsQuic = fetchRPS(index(windowsKernel.data, ["rps-quic"], null), windowsKernelLatencyQuic[windowsKernelLatencyQuic.length - 1]);

    // Compute scores
    windowsPerfScoreRps = (windowsRpsQuic + windowsRpsTcp) / 1000000;
    linuxPerfScoreRps = (linuxRpsQuic + linuxRpsTcp) / 1000000;
    windowsPerfScoreHps = (windowsHpsQuic + windowsHpsTcp) / 100;
    linuxPerfScoreHps = (linuxHpsQuic + linuxHpsTcp) / 100;
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

  const azureWS2025 = (
    windowsOs.includes("2025") ? `WinPrerelease-Datacenter, build: ${windowsType.split(" ")[1]}` : windowsType
  )

  const envStr = `${env === "lab" && windowsOs.includes("2025") ? `ge_current_directiof_stack, build: ${windowsType.split(" ")[1]}` : azureWS2025} | ${linuxType}`

  let margin = '0px'
  let dir = 'row'

  // Check displayport size
  if (window.innerWidth < 600) {
    margin = '10px'
    dir = 'column'
  }

  return (
    <Container maxWidth="xl">
      <div style={{display: 'flex'}}>
      <Typography variant="h3" sx={{ mb: 5 }}>
        Network Performance Overview
      </Typography>
      </div>
      <div style={{ display: 'flex', flexDirection: dir, alignItems: 'center' }}>
        <Box sx={{ marginBottom: margin}}>
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
              { windowsOs === 'windows-2022-x64' && <MenuItem value='lab'>lab</MenuItem> }
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
              { env === "azure" && <MenuItem value='windows-2025-x64'>windows-2025-x64</MenuItem>}
            </Select>
          </FormControl>
        </Box>
        {/* <br /> */}
        <Box sx={{ minWidth: 120, marginLeft: '10px', marginTop: margin }}>
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
        {/* <Typography variant="h5" sx={{ mb: 5 }}>
          Data based on commit: <a href={`https://github.com/microsoft/msquic/commit/${commitHash}`}>{commitHash}</a>
        </Typography> */}
        <p style={{marginLeft: '10px'}}>Data based on <a href={`https://github.com/microsoft/msquic/commit/${commitHash}`}>commit</a>. <b>Warning: </b> Lab results for Ubuntu is out-of-sync. Will be fixed shortly!</p>
      </div>
      {/* <br /> */}
      <p><b>Windows hardware SKU:</b> {getLatestSkuInformation(env, windowsOs, windows)} | <b>Linux hardware SKU:</b> {getLatestSkuInformation(env, linuxOs, linux)}</p>
      <Grid container spacing={3}>
        <Grid xs={12} sm={6} md={3}>
          <AppWidgetSummary
            title="Windows Throughput Performance Score."
            total={windowsPerfScore}
            color="primary"
            icon={
              <div>
                <img alt="icon" src="/netperf/dist/assets/icons/glass/windows.png" />
                <Button
                  onClick={() =>
                    alert(`
                This score is computed as:

                WINDOWS = download_speed * download_weight + upload_speed * upload_weight

                SCORE = WINDOWS / 10000,

                where download_weight = 0.8, upload_weight = 0.2

                Essentially, we weigh download speed more than upload speed, since most internet users
                are using download a lot more often than upload.
              `)
                  }
                >
                  ?
                </Button>
              </div>
            }
          />
        </Grid>

        <Grid xs={12} sm={6} md={3}>
          <AppWidgetSummary
            title="Linux Throughput Performance Score."
            total={linuxPerfScore}
            color="primary"
            icon={
              <div>
                <img alt="icon" src="/netperf/dist/assets/icons/glass/Ubuntu-Logo.png" />
                <Button
                  onClick={() =>
                    alert(`
                This score is computed as:

                LINUX = download_speed * download_weight + upload_speed * upload_weight

                SCORE = LINUX / 10000,

                where download_weight = 0.8, upload_weight = 0.2

                Essentially, we weigh download speed more than upload speed, since most internet users
                are using download a lot more often than upload.

            `)
                  }
                >
                  ?
                </Button>
              </div>
            }
          />
        </Grid>
        <Grid xs={12} sm={6} md={3}>
          <AppWidgetSummary
            title="Windows Latency Performance Score."
            total={windowsPerfScoreLatency}
            color="primary"
            icon={
              <div>
                <img alt="icon" src="/netperf/dist/assets/icons/glass/windows.png" />
                <Button
                  onClick={() =>
                    alert(`
                  This score is computed as:

                  We give a weighting to how important each percentile is:

                  0th percentile, 50th percentile, 90th percentile, 99th percentile, 99.99th percentile, 99.999th percentile, 99.9999th percentile

                  The weights we used are weightings = [0.05, 0.1, 0.2, 0.3, 0.1, 0.1, 0.1, 0.05].

                  We think its important that in the 90th - 99.999th percentiles, we optimize it the most, since most
                  power users (Azure customers) will experience these latencies.

                  Therefore, we give less weighting to the perfect case (0th percentile).
                `)
                  }
                >
                  ?
                </Button>
              </div>
            }
          />
        </Grid>

        <Grid xs={12} sm={6} md={3}>
          <AppWidgetSummary
            title="Linux Latency Performance Score."
            total={linuxPerfScoreLatency}
            color="primary"
            icon={
              <div>
                <img alt="icon" src="/netperf/dist/assets/icons/glass/Ubuntu-Logo.png" />
                <Button
                  onClick={() =>
                    alert(`
              This score is computed as:

              This score is computed as:

              We give a weighting to how important each percentile is:

              0th percentile, 50th percentile, 90th percentile, 99th percentile, 99.99th percentile, 99.999th percentile, 99.9999th percentile

              The weights we used are weightings = [0.05, 0.1, 0.2, 0.3, 0.1, 0.1, 0.1, 0.05].

              We think its important that in the 90th - 99.999th percentiles, we optimize it the most, since most
              power users (Azure customers) will experience these latencies.

              Therefore, we give less weighting to the perfect case (0th percentile).

            `)
                  }
                >
                  ?
                </Button>
              </div>
            }
          />
        </Grid>
        {/* Throughput */}
        <Grid xs={12} md={6} lg={6}>
          <AppWebsiteVisits
            title="Throughput Comparison (kbps), higher the better."
            subheader={` ${envStr}`}
            chart={{
              labels: ['', 'Download', 'Upload', ''],
              series: [
                {
                  name: 'TCP + iocp',
                  type: 'column',
                  fill: 'solid',
                  data: [
                    0,
                    windowsDownloadThroughputTcp,
                    windowsUploadThroughputTcp,
                    0,
                  ],
                },
                {
                  name: 'QUIC + iocp',
                  type: 'column',
                  fill: 'solid',
                  data: [
                    0,
                    windowsDownloadThroughputQuic,
                    windowsUploadThroughputQuic,
                    0,
                  ],
                },

                {
                  name: 'TCP + epoll',
                  type: 'column',
                  fill: 'solid',
                  data: [
                    0,
                    linuxDownloadThroughputTcp,
                    linuxUploadThroughputTcp,
                    0,
                  ],
                },

                {
                  name: 'QUIC + epoll',
                  type: 'column',
                  fill: 'solid',
                  data: [
                    0,
                    linuxDownloadThroughputQuic,
                    linuxUploadThroughputQuic,
                    0,
                  ],
                },

                {
                  name: 'QUIC + winXDP',
                  type: 'column',
                  fill: 'solid',
                  data: [
                    0,
                    windowsXdpDownloadThroughputQuic,
                    windowsXdpUploadThroughputQuic,
                    0,
                  ],
                },
                {
                  name: 'QUIC + wsk',
                  type: 'column',
                  fill: 'solid',
                  data: [
                    0,
                    windowsKernelDownloadThroughputQuic,
                    windowsKernelUploadThroughputQuic,
                    0,
                  ],
                }
              ].filter((item) => { // excludes items with all -1
                for (const data of item.data) {
                  if (data !== -1) {
                    return true
                  }
                }
                return false;
              }).map((item) => {
                item.data = item.data.filter((x) => x !== -1); // filters out the -1 from existing entries
                return item;
              }),
            }}
          />
        </Grid>
        {/* Latency */}
        <Grid xs={12} md={6} lg={6}>
          <AppWebsiteVisits
            title="Latency Comparison (µs), lower the better."
            subheader={` ${envStr}`}
            chart={{
              // New labels based on percentiles
              labels: [
                '50th percentile',
                '90th percentile',
                '99th percentile',
                '99.99th percentile',
              ],
              series: [
                {
                  name: 'TCP + iocp',
                  type: 'column',
                  fill: 'solid',
                  // Data based on Windows TCP for each percentile
                  data: [
                    windowsLatencyTcp[1],
                    windowsLatencyTcp[2],
                    windowsLatencyTcp[3],
                    windowsLatencyTcp[4],
                  ],
                },
                {
                  name: 'QUIC + iocp',
                  type: 'column',
                  fill: 'solid',
                  // Data based on Windows QUIC for each percentile
                  data: [
                    windowsLatencyQuic[1],
                    windowsLatencyQuic[2],
                    windowsLatencyQuic[3],
                    windowsLatencyQuic[4],
                  ],
                },
                {
                  name: 'TCP + epoll',
                  type: 'column',
                  fill: 'solid',
                  // Data based on Linux TCP for each percentile
                  data: [
                    linuxLatencyTcp[1],
                    linuxLatencyTcp[2],
                    linuxLatencyTcp[3],
                    linuxLatencyTcp[4],
                  ],
                },
                {
                  name: 'QUIC + epoll',
                  type: 'column',
                  fill: 'solid',
                  // Data based on Linux QUIC for each percentile
                  data: [
                    linuxLatencyQuic[1],
                    linuxLatencyQuic[2],
                    linuxLatencyQuic[3],
                    linuxLatencyQuic[4],
                  ],
                },
                {
                  name: 'QUIC + winXDP',
                  type: 'column',
                  fill: 'solid',
                  // Data based on Linux TCP for each percentile
                  data: [
                    windowsXdpLatencyQuic[1],
                    windowsXdpLatencyQuic[2],
                    windowsXdpLatencyQuic[3],
                    windowsXdpLatencyQuic[4],
                  ],
                },
                {
                  name: 'QUIC + Wsk',
                  type: 'column',
                  fill: 'solid',
                  // Data based on Linux TCP for each percentile
                  data: [
                    windowsKernelLatencyQuic[1],
                    windowsKernelLatencyQuic[2],
                    windowsKernelLatencyQuic[3],
                    windowsKernelLatencyQuic[4],
                  ],
                }
              ].filter((item) => { // excludes items with all -1
                for (const data of item.data) {
                  if (data !== -1) {
                    return true
                  }
                }
                return false;
              }).map((item) => {
                item.data = item.data.filter((x) => x !== -1); // filters out the -1 from existing entries
                return item;
              }),
            }}
          />
        </Grid>

        <Grid xs={12} sm={6} md={3}>
          <AppWidgetSummary
            title="Windows RPS Performance Score."
            total={windowsPerfScoreRps}
            color="primary"
            icon={
              <div>
                <img alt="icon" src="/netperf/dist/assets/icons/glass/windows.png" />
                <Button
                  onClick={() =>
                    alert(`
                  This score is computed as:
                  windowsPerfScoreRps = (windowsRpsQuic + windowsRpsTcp) / 1000000;

                `)
                  }
                >
                  ?
                </Button>
              </div>
            }
          />
        </Grid>
        <Grid xs={12} sm={6} md={3}>
          <AppWidgetSummary
            title="Linux RPS Performance Score."
            total={linuxPerfScoreRps}
            color="primary"
            icon={
              <div>
                <img alt="icon" src="/netperf/dist/assets/icons/glass/Ubuntu-Logo.png" />
                <Button
                  onClick={() =>
                    alert(`
                This score is computed as:
                linuxPerfScoreRps = (linuxRpsQuic + linuxRpsTcp) / 1000000;

            `)
                  }
                >
                  ?
                </Button>
              </div>
            }
          />
        </Grid>

        <Grid xs={12} sm={6} md={3}>
          <AppWidgetSummary
            title="Windows HPS Performance Score."
            total={windowsPerfScoreHps}
            color="primary"
            icon={
              <div>
                <img alt="icon" src="/netperf/dist/assets/icons/glass/windows.png" />
                <Button
                  onClick={() =>
                    alert(`
                  This score is computed as:
                  windowsPerfScoreHps = (windowsHpsQuic + windowsHpsTcp) / 100;
                `)
                  }
                >
                  ?
                </Button>
              </div>
            }
          />
        </Grid>
        <Grid xs={12} sm={6} md={3}>
          <AppWidgetSummary
            title="Linux HPS Performance Score."
            total={linuxPerfScoreHps}
            color="primary"
            icon={
              <div>
                <img alt="icon" src="/netperf/dist/assets/icons/glass/Ubuntu-Logo.png" />
                <Button
                  onClick={() =>
                    alert(`
                This score is computed as:

                linuxPerfScoreHps = (linuxHpsQuic + linuxHpsTcp) / 100;
            `)
                  }
                >
                  ?
                </Button>
              </div>
            }
          />
        </Grid>
        {/* RPS */}
        <Grid xs={12} md={6} lg={6}>
          <AppWebsiteVisits
            title="RPS Comparison (requests per second), higher the better."
            subheader={` ${envStr}`}
            chart={{
              labels: ['RPS'],
              series: [
                {
                  name: 'TCP + iocp',
                  type: 'column',
                  fill: 'solid',
                  data: [
                    windowsRpsTcp,
                  ],
                },
                {
                  name: 'QUIC + iocp',
                  type: 'column',
                  fill: 'solid',
                  data: [
                    windowsRpsQuic,
                  ],
                },
                {
                  name: 'TCP + epoll',
                  type: 'column',
                  fill: 'solid',
                  data: [
                    linuxRpsTcp,
                  ],
                },
                {
                  name: 'QUIC + epoll',
                  type: 'column',
                  fill: 'solid',
                  data: [
                    linuxRpsQuic,
                  ],
                },

                {
                  name: 'QUIC + winXDP',
                  type: 'column',
                  fill: 'solid',
                  data: [
                    windowsXdpRpsQuic,
                  ],
                },

                {
                  name: 'QUIC + wsk',
                  type: 'column',
                  fill: 'solid',
                  data: [
                    windowsKernelRpsQuic,
                  ],
                },

              ].filter((item) => { // excludes items with all -1
                for (const data of item.data) {
                  if (data !== -1) {
                    return true
                  }
                }
                return false;
              }).map((item) => {
                item.data = item.data.filter((x) => x !== -1); // filters out the -1 from existing entries
                return item;
              }),
            }}
          />
        </Grid>
        {/* HPS */}
        <Grid xs={12} md={6} lg={6}>
          <AppWebsiteVisits
            title="HPS Comparison (handshakes per second), higher the better."
            subheader={`${envStr}`}
            chart={{
              labels: ['HPS'],
              series: [
                {
                  name: 'TCP + iocp',
                  type: 'column',
                  fill: 'solid',
                  data: [
                    windowsHpsTcp
                  ],
                },
                {
                  name: 'QUIC + iocp',
                  type: 'column',
                  fill: 'solid',
                  data: [
                    windowsHpsQuic
                  ],
                },

                {
                  name: 'TCP + epoll',
                  type: 'column',
                  fill: 'solid',
                  data: [
                    linuxHpsTcp
                  ],
                },

                {
                  name: 'QUIC + epoll',
                  type: 'column',
                  fill: 'solid',
                  data: [
                    linuxHpsQuic
                  ],
                },

                {
                  name: 'QUIC + winxdp',
                  type: 'column',
                  fill: 'solid',
                  data: [
                    windowsXdpHpsQuic
                  ],
                },

              ].filter((item) => { // excludes items with all -1
                for (const data of item.data) {
                  if (data !== -1) {
                    return true
                  }
                }
                return false;
              }).map((item) => {
                item.data = item.data.filter((x) => x !== -1); // filters out the -1 from existing entries
                return item;
              }),
            }}
          />
        </Grid>

      </Grid>
    </Container>
  );
}
