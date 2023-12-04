import { Helmet } from 'react-helmet-async';
import { useState, useEffect } from 'react';

import Grid from '@mui/material/Unstable_Grid2';
import Container from '@mui/material/Container';
import Typography from '@mui/material/Typography';

import { GraphView } from 'src/sections/overview/graphing';


// ----------------------------------------------------------------------

export default function ThroughputPage() {

  // TODO: Once you have the pipeline to auto-update based on the last ~20 commits, update this URL.
  const URL = "https://microsoft.github.io/netperf/data/secnetperf/2023-12-01-20-25-09._.67ee09354f52d014ad4e9ec85fcb6b9260890134.json/test_result.json";

  const [data, setData] = useState(null);
  const [isLoading, setIsLoading] = useState(true);
  const [error, setError] = useState(null);


  useEffect(() => {
    fetch(URL)
        .then(response => {
            if (!response.ok) {
                throw new Error('Network response was not ok');
            }
            return response.json();
        })
        .then(json => {
            setData(json);
            setIsLoading(false);
        })
        .catch(err => {
            setError(err);
            setIsLoading(false);
        });
  }, []);

  if (isLoading) {
    console.log("Loading...");
  }

  if (error) {
    console.log("Error!");
  }

  if (data) {
    console.log(data);
  }

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
          <GraphView title="Download Throughput"
            subheader='Tested using Windows 11 build 22000.282, Linux Ubuntu 20.04.3 LTS'
            labels={['Commit 1', 'Commit 2', 'Commit 3', 'Commit 4', 'Commit 5', 'Commit 6']}
            series={[
              {
                name: 'Linux + TCP',
                type: 'line',
                fill: 'solid',
                data: [23, 30, 22, 43, 32, 44],

              },
              {
                name: 'Windows + TCP',
                type: 'line',
                fill: 'solid',
                data: [10, 5, 21, 12, 32, 44],
              },
              {
                name: 'Linux + QUIC',
                type: 'line',
                fill: 'solid',
                data: [32, 43, 53, 43, 24, 44],
              },
              {
                name: 'Windows + QUIC',
                type: 'line',
                fill: 'solid',
                data: [50, 55, 34, 23, 78, 44],
              },
            ]}
          />
          <GraphView title="Upload Throughput"
            subheader='Tested using Windows 11 build 22000.282, Linux Ubuntu 20.04.3 LTS'
            labels={['Commit 1', 'Commit 2', 'Commit 3', 'Commit 4', 'Commit 5', 'Commit 6']}
            series={[
              {
                name: 'Linux + TCP',
                type: 'line',
                fill: 'solid',
                data: [23, 30, 22, 43, 32, 44],

              },
              {
                name: 'Windows + TCP',
                type: 'line',
                fill: 'solid',
                data: [10, 5, 21, 12, 32, 44],
              },
              {
                name: 'Linux + QUIC',
                type: 'line',
                fill: 'solid',
                data: [32, 43, 53, 43, 24, 44],
              },
              {
                name: 'Windows + QUIC',
                type: 'line',
                fill: 'solid',
                data: [50, 55, 34, 23, 78, 44],
              },
            ]}
          />
        </Grid>
      </Container>
    </>
  );
}
