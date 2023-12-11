import { Helmet } from 'react-helmet-async';

import Grid from '@mui/material/Unstable_Grid2';
import Container from '@mui/material/Container';
import Typography from '@mui/material/Typography';

import useFetchData from 'src/hooks/use-fetch-data';

import { GraphView } from 'src/sections/overview/graphing';

// import {
//   parseLinuxDownloadQuic,
//   parseLinuxDownloadTcp,
//   parseLinuxUploadQuic,
//   parseLinuxUploadTcp,
//   parseWindowsDownloadQuic,
//   parseWindowsDownloadTcp,
//   parseWindowsUploadQuic,
//   parseWindowsUploadTcp,
//   parseCommitsList,
//   parseRunDates,
// } from './util/parser';



// ----------------------------------------------------------------------

export default function ThroughputPage() {

  // const URL = "https://microsoft.github.io/netperf/data/secnetperf/dashboard.json";
  // const { data, isLoading, error } = useFetchData(URL);

  const uploadThroughput = <div />
  // let downloadThroughput = <div />

  // if (isLoading) {
  //   console.log("Loading...");
  // }

  // if (error) {
  //   console.log("Error!");
  // }

  // if (data) {
  //   console.log(data);
  //   const commits = parseCommitsList(data);
  //   const runDates = parseRunDates(data);
  //   const windowsTcpUpload = parseWindowsUploadTcp(data);
  //   const windowsTcpDownload = parseWindowsDownloadTcp(data);
  //   const windowsQuicUpload = parseWindowsUploadQuic(data);
  //   const windowsQuicDownload = parseWindowsDownloadQuic(data);
  //   const linuxTcpUpload = parseLinuxUploadTcp(data);
  //   const linuxTcpDownload = parseLinuxDownloadTcp(data);
  //   const linuxQuicUpload = parseLinuxUploadQuic(data);
  //   const linuxQuicDownload = parseLinuxDownloadQuic(data);

  //   uploadThroughput = <GraphView title="Upload Throughput"
  //   subheader='Tested using Windows Server 2022 (Client and Server). Linux Ubuntu 20.04.3 LTS (Client and Server)'
  //   labels={commits}
  //   series={[
  //     {
  //       name: 'Linux + TCP',
  //       type: 'line',
  //       fill: 'solid',
  //       data: linuxTcpUpload,

  //     },
  //     {
  //       name: 'Windows + TCP',
  //       type: 'line',
  //       fill: 'solid',
  //       data: windowsTcpUpload,
  //     },
  //     {
  //       name: 'Linux + QUIC',
  //       type: 'line',
  //       fill: 'solid',
  //       data: linuxQuicUpload,
  //     },
  //     {
  //       name: 'Windows + QUIC',
  //       type: 'line',
  //       fill: 'solid',
  //       data: windowsQuicUpload,
  //     },
  //   ]} />
  //   downloadThroughput = <GraphView title="Download Throughput"
  //   subheader='Tested using Windows 11 build 22000.282, Linux Ubuntu 20.04.3 LTS'
  //   labels={commits}
  //   series={[
  //     {
  //       name: 'Linux + TCP',
  //       type: 'line',
  //       fill: 'solid',
  //       data: linuxTcpDownload,

  //     },
  //     {
  //       name: 'Windows + TCP',
  //       type: 'line',
  //       fill: 'solid',
  //       data: windowsTcpDownload,
  //     },
  //     {
  //       name: 'Linux + QUIC',
  //       type: 'line',
  //       fill: 'solid',
  //       data: linuxQuicDownload,
  //     },
  //     {
  //       name: 'Windows + QUIC',
  //       type: 'line',
  //       fill: 'solid',
  //       data: windowsQuicDownload,
  //     },
  //   ]}
  // />
  // }

  return (
    <>
      <Helmet>
        <title> Netperf </title>
      </Helmet>

      <Container maxWidth="xl">
        <Typography variant="h3" sx={{ mb: 5 }}>
          Detailed Throughput
        </Typography>
        <Grid container spacing={3}>
          {uploadThroughput}
        </Grid>
      </Container>
    </>
  );
}
