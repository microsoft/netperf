import { Helmet } from 'react-helmet-async';

import Grid from '@mui/material/Unstable_Grid2';
import Container from '@mui/material/Container';
import Typography from '@mui/material/Typography';

import { GraphView } from 'src/sections/overview/graphing';

// ----------------------------------------------------------------------

export default function HpsPage() {
  return (
    <>
      <Helmet>
        <title> Netperf </title>
      </Helmet>

      <Container maxWidth="xl">
        <Typography variant="h3" sx={{ mb: 5 }}>
          Handshakes Per Second - TODO
        </Typography>
        <Grid container spacing={3}>
          {/* <GraphView title="HPS"

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
          /> */}
        </Grid>
      </Container>
    </>
  );
}
