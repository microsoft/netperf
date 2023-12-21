// import { faker } from '@faker-js/faker';
import Button from '@mui/material/Button';
import Container from '@mui/material/Container';
import Grid from '@mui/material/Unstable_Grid2';
import Typography from '@mui/material/Typography';
// import Iconify from 'src/components/iconify';

import useFetchData from 'src/hooks/use-fetch-data';
// import AppTasks from '../app-tasks';
// import AppNewsUpdate from '../app-news-update';
// import AppOrderTimeline from '../app-order-timeline';
// import AppCurrentVisits from '../app-current-visits';
import AppWebsiteVisits from '../app-website-visits';
import AppWidgetSummary from '../app-widget-summary';
// import AppTrafficBySite from '../app-traffic-by-site';
// import AppCurrentSubject from '../app-current-subject';
// import AppConversionRates from '../app-conversion-rates';



function throughputPerformance(download, upload, dweight, uweight) {
  return ((download * dweight) + (upload * uweight)) / 10000;
}

function latencyPerformance(latencies) {
  let weighting = [0.05, 0.1, 0.2, 0.3, 0.1, 0.1, 0.1, 0.05]
  let sum = 1.0
  for (let i = 0; i < latencies.length; i++) {
    sum += weighting[i] * latencies[i]
  }
  return (1 / sum) * 100000
}


// ----------------------------------------------------------------------

export default function AppView() {
  const windows = useFetchData("https://raw.githubusercontent.com/microsoft/netperf/deploy/json-test-results-windows-windows-2022-x64-schannel.json");
  const linux = useFetchData("https://raw.githubusercontent.com/microsoft/netperf/deploy/json-test-results-linux-ubuntu-20.04-x64-openssl.json");


  let windowsPerfScore = 0
  let linuxPerfScore = 0

  let windowsPerfScoreLatency = 0
  let linuxPerfScoreLatency = 0

  let windowsUploadThroughputQuic = 1
  let windowsUploadThroughputTcp = 1
  let windowsDownloadThroughputQuic = 1
  let windowsDownloadThroughputTcp = 1

  let linuxDownloadThroughputQuic = 1
  let linuxDownloadThroughputTcp = 1
  let linuxUploadThroughputQuic = 1
  let linuxUploadThroughputTcp = 1

  let windowsLatencyQuic = [0, 0, 0, 0, 0, 0, 0, 0]
  let windowsLatencyTcp = [0, 0, 0, 0, 0, 0, 0, 0]
  let linuxLatencyQuic = [0, 0, 0, 0, 0, 0, 0, 0]
  let linuxLatencyTcp = [0, 0, 0, 0, 0, 0, 0, 0]

  let windowsType = "Windows Server 2022";
  let linuxType = "Linux Ubuntu 20.04 LTS"

  if (windows.data && linux.data) {
    for (const key of Object.keys(windows.data)) {
      if (key.includes("download") && key.includes("quic")) {
        windowsDownloadThroughputQuic = windows.data[key];
      }
      if (key.includes("download") && key.includes("tcp")) {
        windowsDownloadThroughputTcp = windows.data[key];
      }
      if (key.includes("upload") && key.includes("quic")) {
        windowsUploadThroughputQuic = windows.data[key];
      }
      if (key.includes("upload") && key.includes("tcp")) {
        windowsUploadThroughputTcp = windows.data[key];
      }
      if (key.includes("rps") && key.includes("quic")) {
        windowsLatencyQuic = windows.data[key];
      }
      if (key.includes("rps") && key.includes("tcp")) {
        windowsLatencyTcp = windows.data[key];
      }
    }

    for (const key of Object.keys(linux.data)) {
      if (key.includes("download") && key.includes("quic")) {
        linuxDownloadThroughputQuic = linux.data[key];
      }
      if (key.includes("download") && key.includes("tcp")) {
        linuxDownloadThroughputTcp = linux.data[key];
      }
      if (key.includes("upload") && key.includes("quic")) {
        linuxUploadThroughputQuic = linux.data[key];
      }
      if (key.includes("upload") && key.includes("tcp")) {
        linuxUploadThroughputTcp = linux.data[key];
      }
      if (key.includes("rps") && key.includes("quic")) {
        linuxLatencyQuic = linux.data[key];
      }
      if (key.includes("rps") && key.includes("tcp")) {
        linuxLatencyTcp = linux.data[key];
      }
    }

    windowsPerfScore = throughputPerformance(windowsDownloadThroughputQuic, windowsUploadThroughputQuic, 0.8, 0.2);
    linuxPerfScore = throughputPerformance(linuxDownloadThroughputQuic, linuxUploadThroughputQuic, 0.8, 0.2);
    
    windowsPerfScoreLatency = latencyPerformance(windowsLatencyQuic);
    linuxPerfScoreLatency = latencyPerformance(linuxLatencyQuic);
    console.log(windowsPerfScoreLatency)
    console.log(linuxPerfScoreLatency)
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

      {/* <p>Data as of 10/10/2023 (Latest Commit)</p> */}
      {/* <Typography variant="h6" sx={{ mb: 5 }}>
        Network Performance Overview
      </Typography> */}

      <Grid container spacing={3}>
        {/* <Grid xs={12} sm={6} md={3}>
          <AppWidgetSummary
            title="Weekly Sales"
            total={714000}
            color="success"
            icon={<img alt="icon" src="/assets/icons/glass/ic_glass_bag.png" />}
          />
        </Grid>

        <Grid xs={12} sm={6} md={3}>
          <AppWidgetSummary
            title="New Users"
            total={1352831}
            color="info"
            icon={<img alt="icon" src="/assets/icons/glass/ic_glass_users.png" />}
          />
        </Grid>

        <Grid xs={12} sm={6} md={3}>
          <AppWidgetSummary
            title="Item Orders"
            total={1723315}
            color="warning"
            icon={<img alt="icon" src="/assets/icons/glass/ic_glass_buy.png" />}
          />
        </Grid> */}

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
                >?</Button>
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
                >?</Button>
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
                  data: [windowsDownloadThroughputTcp, windowsUploadThroughputTcp, linuxDownloadThroughputTcp, linuxUploadThroughputTcp],
                },
                {
                  name: 'QUIC',
                  type: 'column',
                  fill: 'solid',
                  data: [windowsDownloadThroughputQuic, windowsUploadThroughputQuic, linuxDownloadThroughputQuic, linuxUploadThroughputQuic],
                },
              ],
            }}
          />
        </Grid>
        {/*
        <Grid xs={12} sm={6} md={3}>
          <AppWidgetSummary
            title="Bug Reports"
            total={234}
            color="error"
            icon={<img alt="icon" src="/assets/icons/glass/ic_glass_message.png" />}
          />
        </Grid>

        <Grid xs={12} sm={6} md={3}>
          <AppWidgetSummary
            title="Bug Reports"
            total={234}
            color="error"
            icon={<img alt="icon" src="/assets/icons/glass/ic_glass_message.png" />}
          />
        </Grid>

        <Grid xs={12} sm={6} md={3}>
          <AppWidgetSummary
            title="Bug Reports"
            total={234}
            color="error"
            icon={<img alt="icon" src="/assets/icons/glass/ic_glass_message.png" />}
          />
        </Grid>

        <Grid xs={12} sm={6} md={3}>
          <AppWidgetSummary
            title="Bug Reports"
            total={234}
            color="error"
            icon={<img alt="icon" src="/assets/icons/glass/ic_glass_message.png" />}
          />
        </Grid> */}

        <Grid xs={12} md={6} lg={6}>
          <AppWebsiteVisits
            title="Latency Comparison (ms), lower the better."
            subheader="Tested using Windows 11 build 22000.282, Linux Ubuntu 20.04.3 LTS"
            chart={{
              labels: ['Windows QUIC', 'Windows TCP', 'Linux QUIC', 'Linux TCP'],
              series: [
                {
                  name: '50th percentile',
                  type: 'column',
                  fill: 'solid',
                  data: [windowsLatencyQuic[1], windowsLatencyTcp[1], linuxLatencyQuic[1], linuxLatencyTcp[1]],
                },
                {
                  name: '90th percentile',
                  type: 'column',
                  fill: 'solid',
                  data: [windowsLatencyQuic[2], windowsLatencyTcp[2], linuxLatencyQuic[2], linuxLatencyTcp[2]],
                },
                {
                  name: '99th percentile',
                  type: 'column',
                  fill: 'solid',
                  data: [windowsLatencyQuic[3], windowsLatencyTcp[3], linuxLatencyQuic[3], linuxLatencyTcp[3]],
                },
                {
                  name: '99.99th percentile',
                  type: 'column',
                  fill: 'solid',
                  data: [windowsLatencyQuic[4], windowsLatencyTcp[4], linuxLatencyQuic[4], linuxLatencyTcp[4]],
                },
              ],
            }}
          />
        </Grid>

        {/* <Grid xs={12} md={6} lg={4}>
          <AppCurrentVisits
            title="Current Visits"
            chart={{
              series: [
                { label: 'America', value: 4344 },
                { label: 'Asia', value: 5435 },
                { label: 'Europe', value: 1443 },
                { label: 'Africa', value: 4443 },
              ],
            }}
          />
        </Grid> */}

        {/* <Grid xs={12} md={6} lg={8}>
          <AppConversionRates
            title="Conversion Rates"
            subheader="(+43%) than last year"
            chart={{
              series: [
                { label: 'Italy', value: 400 },
                { label: 'Japan', value: 430 },
                { label: 'China', value: 448 },
                { label: 'Canada', value: 470 },
                { label: 'France', value: 540 },
                { label: 'Germany', value: 580 },
                { label: 'South Korea', value: 690 },
                { label: 'Netherlands', value: 1100 },
                { label: 'United States', value: 1200 },
                { label: 'United Kingdom', value: 1380 },
              ],
            }}
          />
        </Grid> */}

        {/* <Grid xs={12} md={6} lg={4}>
          <AppCurrentSubject
            title="Current Subject"
            chart={{
              categories: ['English', 'History', 'Physics', 'Geography', 'Chinese', 'Math'],
              series: [
                { name: 'Series 1', data: [80, 50, 30, 40, 100, 20] },
                { name: 'Series 2', data: [20, 30, 40, 80, 20, 80] },
                { name: 'Series 3', data: [44, 76, 78, 13, 43, 10] },
              ],
            }}
          />
        </Grid> */}

        {/* <Grid xs={12} md={6} lg={8}>
          <AppNewsUpdate
            title="News Update"
            list={[...Array(5)].map((_, index) => ({
              id: faker.string.uuid(),
              title: faker.person.jobTitle(),
              description: faker.commerce.productDescription(),
              image: `/assets/images/covers/cover_${index + 1}.jpg`,
              postedAt: faker.date.recent(),
            }))}
          />
        </Grid> */}

        {/* <Grid xs={12} md={6} lg={4}>
          <AppOrderTimeline
            title="Order Timeline"
            list={[...Array(5)].map((_, index) => ({
              id: faker.string.uuid(),
              title: [
                '1983, orders, $4220',
                '12 Invoices have been paid',
                'Order #37745 from September',
                'New order placed #XF-2356',
                'New order placed #XF-2346',
              ][index],
              type: `order${index + 1}`,
              time: faker.date.past(),
            }))}
          />
        </Grid> */}

        {/* <Grid xs={12} md={6} lg={4}>
          <AppTrafficBySite
            title="Traffic by Site"
            list={[
              {
                name: 'FaceBook',
                value: 323234,
                icon: <Iconify icon="eva:facebook-fill" color="#1877F2" width={32} />,
              },
              {
                name: 'Google',
                value: 341212,
                icon: <Iconify icon="eva:google-fill" color="#DF3E30" width={32} />,
              },
              {
                name: 'Linkedin',
                value: 411213,
                icon: <Iconify icon="eva:linkedin-fill" color="#006097" width={32} />,
              },
              {
                name: 'Twitter',
                value: 443232,
                icon: <Iconify icon="eva:twitter-fill" color="#1C9CEA" width={32} />,
              },
            ]}
          />
        </Grid> */}

        {/* <Grid xs={12} md={6} lg={8}>
          <AppTasks
            title="Tasks"
            list={[
              { id: '1', name: 'Create FireStone Logo' },
              { id: '2', name: 'Add SCSS and JS files if required' },
              { id: '3', name: 'Stakeholder Meeting' },
              { id: '4', name: 'Scoping & Estimations' },
              { id: '5', name: 'Sprint Showcase' },
            ]}
          />
        </Grid> */}
      </Grid>
    </Container>
  );
}
