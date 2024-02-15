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




function throughputPerformance(download, upload, dweight, uweight) {
  return (download * dweight + upload * uweight) / 10000;
}

function latencyPerformance(latencies) {
  const weighting = [0.05, 0.1, 0.2, 0.3, 0.1, 0.1, 0.1, 0.05];
  let sum = 1.0;
  for (let i = 0; i < 8; i += 1) {
    sum += weighting[i] * latencies[i];
  }
  return (1 / sum) * 100000;
}

// ----------------------------------------------------------------------

export default function AppView() {

  const [env, setEnv] = useState('azure');

  const windows = useFetchData(
    `https://raw.githubusercontent.com/microsoft/netperf/deploy/json-test-results-${env}-windows-windows-2022-x64-schannel-iocp.json/json-test-results-${env}-windows-windows-2022-x64-schannel-iocp.json`
  );
  const linux = useFetchData(
    `https://raw.githubusercontent.com/microsoft/netperf/deploy/json-test-results-${env}-linux-ubuntu-20.04-x64-openssl-epoll.json/json-test-results-${env}-linux-ubuntu-20.04-x64-openssl-epoll.json`
  );

  const windowsXdp = useFetchData(
    `https://raw.githubusercontent.com/microsoft/netperf/deploy/json-test-results-${env}-windows-windows-2022-x64-schannel-xdp.json/json-test-results-${env}-windows-windows-2022-x64-schannel-xdp.json`
  );

  const windowsKernel = useFetchData(
    `https://raw.githubusercontent.com/microsoft/netperf/deploy/json-test-results-${env}-windows-windows-2022-x64-schannel-wsk.json/json-test-results-${env}-windows-windows-2022-x64-schannel-wsk.json`
  );

  let windowsPerfScore = 0;
  let linuxPerfScore = 0;

  let windowsPerfScoreLatency = 0;
  let linuxPerfScoreLatency = 0;

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
  const windowsType = 'Windows Server 2022';
  const linuxType = 'Linux Ubuntu 20.04 LTS';

  function index(object, key, defaultValue) {
    return object[key] || defaultValue;
  }

  if (windows.data && linux.data && windowsXdp.data && windowsKernel.data) {
    commitHash = windows.data.commit;
    // Throughput
    windowsDownloadThroughputQuic = Math.max(...index(windows.data, "tput-down-quic", [-1]));
    windowsDownloadThroughputTcp = Math.max(...index(windows.data, "tput-down-tcp", [-1]));
    windowsUploadThroughputQuic = Math.max(...index(windows.data, "tput-up-quic", [-1]));
    windowsUploadThroughputTcp = Math.max(...index(windows.data, "tput-up-tcp", [-1]));
    linuxDownloadThroughputQuic = Math.max(...index(linux.data, "tput-down-quic", [-1]));
    linuxDownloadThroughputTcp = Math.max(...index(linux.data, "tput-down-tcp", [-1]));
    linuxUploadThroughputQuic = Math.max(...index(linux.data, "tput-up-quic", [-1]));
    linuxUploadThroughputTcp = Math.max(...index(linux.data, "tput-up-tcp", [-1]));
    windowsKernelDownloadThroughputQuic = Math.max(...index(windowsKernel.data, "tput-down-quic", [-1]));
    windowsKernelUploadThroughputQuic = Math.max(...index(windowsKernel.data, "tput-up-quic", [-1]));
    windowsXdpDownloadThroughputQuic = Math.max(...index(windowsXdp.data, "tput-down-quic", [-1]));
    windowsXdpUploadThroughputQuic = Math.max(...index(windowsXdp.data, "tput-up-quic", [-1]));

    // Latency
    windowsLatencyQuic = index(windows.data, "rps-up-512-down-4000-quic", windowsLatencyQuic);
    windowsLatencyTcp = index(windows.data, "rps-up-512-down-4000-tcp", windowsLatencyTcp);
    linuxLatencyQuic = index(linux.data, "rps-up-512-down-4000-quic", linuxLatencyQuic);
    linuxLatencyTcp = index(linux.data, "rps-up-512-down-4000-tcp", linuxLatencyTcp);
    windowsXdpLatencyQuic = index(windowsXdp.data, "rps-up-512-down-4000-quic", windowsXdpLatencyQuic)
    windowsKernelLatencyQuic = index(windowsKernel.data, "rps-up-512-down-4000-quic", windowsKernelLatencyQuic)


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
    windowsHpsQuic = Math.max(...index(windows.data, "hps-conns-100-quic", [-1]));
    windowsHpsTcp = Math.max(...index(windows.data, "hps-conns-100-tcp", [-1]));
    linuxHpsQuic = Math.max(...index(linux.data, "hps-conns-100-quic", [-1]));
    linuxHpsTcp = Math.max(...index(linux.data, "hps-conns-100-tcp", [-1]));
    windowsXdpHpsQuic = Math.max(...index(windowsXdp.data, "hps-conns-100-quic", [-1]));

    // RPS
    windowsRpsQuic = windowsLatencyQuic[windowsLatencyQuic.length - 1]; // Average across all runs or not?
    windowsRpsTcp = windowsLatencyTcp[windowsLatencyTcp.length - 1];
    linuxRpsQuic = linuxLatencyQuic[linuxLatencyQuic.length - 1];
    linuxRpsTcp = linuxLatencyTcp[linuxLatencyTcp.length - 1];
    windowsXdpRpsQuic = windowsXdpLatencyQuic[windowsXdpLatencyQuic.length - 1];
    windowsKernelRpsQuic = windowsKernelLatencyQuic[windowsKernelLatencyQuic.length - 1];
  }

  const handleChange = (event) => {
    setEnv(event.target.value);
  };

  return (
    <Container maxWidth="xl">
      <Typography variant="h3" sx={{ mb: 5 }}>
        Network Performance Overview
      </Typography>
      <Typography variant="h5" sx={{ mb: 5 }}>
        Data based on commit: <a href={`https://github.com/microsoft/msquic/commit/${commitHash}`}>{commitHash}</a>
      </Typography>
      <Box sx={{ minWidth: 120 }}>
        <FormControl fullWidth>
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
            <MenuItem value='lab'>lab</MenuItem>
          </Select>
        </FormControl>
      </Box>
      <br />
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
            subheader={`Tested using ${windowsType}, ${linuxType}`}
            chart={{
              labels: ['Windows Download', 'Windows Upload', 'Linux Download', 'Linux Upload'],
              series: [
                {
                  name: 'TCP',
                  type: 'column',
                  fill: 'solid',
                  data: [
                    windowsDownloadThroughputTcp,
                    windowsUploadThroughputTcp,
                    linuxDownloadThroughputTcp,
                    linuxUploadThroughputTcp,
                  ],
                },
                {
                  name: 'QUIC',
                  type: 'column',
                  fill: 'solid',
                  data: [
                    windowsDownloadThroughputQuic,
                    windowsUploadThroughputQuic,
                    linuxDownloadThroughputQuic,
                    linuxUploadThroughputQuic,
                  ],
                },

                {
                  name: 'QUIC + XDP',
                  type: 'column',
                  fill: 'solid',
                  data: [
                    windowsXdpDownloadThroughputQuic,
                    windowsXdpUploadThroughputQuic,
                  ],
                },
                {
                  name: 'QUIC + Kernel Mode (wsk)',
                  type: 'column',
                  fill: 'solid',
                  data: [
                    windowsKernelDownloadThroughputQuic,
                    windowsKernelUploadThroughputQuic,
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
            subheader={`Tested using ${windowsType}, ${linuxType}`}
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
                  name: 'Windows QUIC',
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
                  name: 'Windows TCP',
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
                  name: 'Linux QUIC',
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
                  name: 'Linux TCP',
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
                  name: 'Windows QUIC + XDP',
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
                  name: 'Windows QUIC + Wsk',
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
            total={0}
            color="primary"
            icon={
              <div>
                <img alt="icon" src="/netperf/dist/assets/icons/glass/windows.png" />
                <Button
                  onClick={() =>
                    alert(`
                  This score is computed as:
                  ??? TODO
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
            total={0}
            color="primary"
            icon={
              <div>
                <img alt="icon" src="/netperf/dist/assets/icons/glass/Ubuntu-Logo.png" />
                <Button
                  onClick={() =>
                    alert(`
                This score is computed as:

                ??? TODO
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
            total={0}
            color="primary"
            icon={
              <div>
                <img alt="icon" src="/netperf/dist/assets/icons/glass/windows.png" />
                <Button
                  onClick={() =>
                    alert(`
                  This score is computed as:
                  ??? TODO
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
            total={0}
            color="primary"
            icon={
              <div>
                <img alt="icon" src="/netperf/dist/assets/icons/glass/Ubuntu-Logo.png" />
                <Button
                  onClick={() =>
                    alert(`
                This score is computed as:

                ??? TODO
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
            subheader={`Tested using ${windowsType}, ${linuxType}`}
            chart={{
              labels: ['TCP', 'QUIC', 'QUIC + XDP', 'QUIC + Wsk'],
              series: [
                {
                  name: 'Windows',
                  type: 'column',
                  fill: 'solid',
                  data: [
                    windowsRpsTcp,
                    windowsRpsQuic,
                    windowsXdpRpsQuic,
                    windowsKernelRpsQuic,
                  ],
                },
                {
                  name: 'Linux',
                  type: 'column',
                  fill: 'solid',
                  data: [
                    linuxRpsTcp,
                    linuxRpsQuic,
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
            subheader={`Tested using ${windowsType}, ${linuxType}`}
            chart={{
              labels: ['TCP', 'QUIC', 'QUIC + XDP'],
              series: [
                {
                  name: 'Windows',
                  type: 'column',
                  fill: 'solid',
                  data: [
                    windowsHpsTcp,
                    windowsHpsQuic,
                    windowsXdpHpsQuic,
                  ],
                },
                {
                  name: 'Linux',
                  type: 'column',
                  fill: 'solid',
                  data: [
                    linuxHpsTcp,
                    linuxHpsQuic,
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
