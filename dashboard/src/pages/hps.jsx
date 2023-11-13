import { Helmet } from 'react-helmet-async';

import { AppView } from 'src/sections/overview/view';

// ----------------------------------------------------------------------

export default function HpsPage() {
  return (
    <>
      <Helmet>
        <title> Netperf </title>
      </Helmet>

      <AppView />
    </>
  );
}
