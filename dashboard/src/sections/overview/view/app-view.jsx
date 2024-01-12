/* eslint-disable no-restricted-syntax */

import Button from '@mui/material/Button';
import Container from '@mui/material/Container';
import Grid from '@mui/material/Unstable_Grid2';
import Typography from '@mui/material/Typography';
import useFetchData from 'src/hooks/use-fetch-data';
import AppWebsiteVisits from '../app-website-visits';
import AppWidgetSummary from '../app-widget-summary';

function throughputPerformance(download, upload, dweight, uweight) {
  return (download * dweight + upload * uweight) / 10000;
}

function latencyPerformance(latencies) {
  const weighting = [0.05, 0.1, 0.2, 0.3, 0.1, 0.1, 0.1, 0.05];
  let sum = 1.0;
  for (let i = 0; i < latencies.length; i += 1) {
    sum += weighting[i] * latencies[i];
  }
  return (1 / sum) * 100000;
}

// ----------------------------------------------------------------------

export default function AppView() {
  const windows = useFetchData(
    'https://raw.githubusercontent.com/microsoft/netperf/deploy/json-test-results-windows-windows-2022-x64-schannel.json'
  );
  const linux = useFetchData(
    'https://raw.githubusercontent.com/microsoft/netperf/deploy/json-test-results-linux-ubuntu-20.04-x64-openssl.json'
  );

  let windowsPerfScore = 0;
  let linuxPerfScore = 0;

  let windowsPerfScoreLatency = 0;
  let linuxPerfScoreLatency = 0;

  let windowsUploadThroughputQuic = 1;
  let windowsUploadThroughputTcp = 1;
  let windowsDownloadThroughputQuic = 1;
  let windowsDownloadThroughputTcp = 1;

  let linuxDownloadThroughputQuic = 1;
  let linuxDownloadThroughputTcp = 1;
  let linuxUploadThroughputQuic = 1;
  let linuxUploadThroughputTcp = 1;

  let windowsLatencyQuic = [0, 0, 0, 0, 0, 0, 0, 0];
  let windowsLatencyTcp = [0, 0, 0, 0, 0, 0, 0, 0];
  let linuxLatencyQuic = [0, 0, 0, 0, 0, 0, 0, 0];
  let linuxLatencyTcp = [0, 0, 0, 0, 0, 0, 0, 0];

  const windowsType = 'Windows Server 2022';
  const linuxType = 'Linux Ubuntu 20.04 LTS';

  if (windows.data && linux.data) {
    for (const key of Object.keys(windows.data)) {
      if (key.includes('download') && key.includes('quic')) {
        windowsDownloadThroughputQuic = windows.data[key];
      }
      if (key.includes('download') && key.includes('tcp')) {
        windowsDownloadThroughputTcp = windows.data[key];
      }
      if (key.includes('upload') && key.includes('quic')) {
        windowsUploadThroughputQuic = windows.data[key];
      }
      if (key.includes('upload') && key.includes('tcp')) {
        windowsUploadThroughputTcp = windows.data[key];
      }
      if (key.includes('latency') && key.includes('quic')) {
        windowsLatencyQuic = windows.data[key];
      }
      if (key.includes('latency') && key.includes('tcp')) {
        windowsLatencyTcp = windows.data[key];
      }
    }

    for (const key of Object.keys(linux.data)) {
      if (key.includes('download') && key.includes('quic')) {
        linuxDownloadThroughputQuic = linux.data[key];
      }
      if (key.includes('download') && key.includes('tcp')) {
        linuxDownloadThroughputTcp = linux.data[key];
      }
      if (key.includes('upload') && key.includes('quic')) {
        linuxUploadThroughputQuic = linux.data[key];
      }
      if (key.includes('upload') && key.includes('tcp')) {
        linuxUploadThroughputTcp = linux.data[key];
      }
      if (key.includes('latency') && key.includes('quic')) {
        linuxLatencyQuic = linux.data[key];
      }
      if (key.includes('latency') && key.includes('tcp')) {
        linuxLatencyTcp = linux.data[key];
      }
    }

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
    console.log(windowsPerfScoreLatency);
    console.log(linuxPerfScoreLatency);
  }

  // LATENCY ARRAY: [0th, 50th, 90th, 99th, 99.9th, 99.99th, 99.999th, 99.9999th]
  // console.log(linuxLatencyQuic)
  // console.log(linuxLatencyTcp)
  // console.log(windowsLatencyQuic)
  // console.log(windowsLatencyTcp)

  return (
    <Container maxWidth="xl">
      <Typography variant="h3" sx={{ mb: 5 }}>
        Network Performance Overview
      </Typography>
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
              ],
            }}
          />
        </Grid>

        <Grid xs={12} md={6} lg={6}>
          <AppWebsiteVisits
            title="Latency Comparison (ms), lower the better."
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
              ],
            }}
          />
        </Grid>
      </Grid>
    </Container>
  );
}
