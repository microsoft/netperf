import { Helmet } from 'react-helmet-async';

import { GraphView } from 'src/sections/overview/graphing';

// ----------------------------------------------------------------------

export default function ThroughputPage() {
  return (
    <>
      <Helmet>
        <title> Netperf </title>
      </Helmet>

      <GraphView title="Detailed Throughput" />
    </>
  );
}
