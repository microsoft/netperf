import { Helmet } from 'react-helmet-async';

import { AppView } from 'src/sections/overview/view';

// ----------------------------------------------------------------------

export default function RpsPage() {
  return (
    <>
      <Helmet>
        <title> Netperf </title>
      </Helmet>

      <AppView />
    </>
  );
}
