/* eslint-disable perfectionist/sort-imports */
/* eslint-disable react-hooks/exhaustive-deps */
import 'src/global.css';

import { useScrollToTop } from 'src/hooks/use-scroll-to-top';
import { useEffect, useState } from 'react';

import Router from 'src/routes/sections';
import ThemeProvider from 'src/theme';
import useSQLiteWorker from 'src/hooks/use-sql-lite';

// ----------------------------------------------------------------------

export default function App() {
  const { exec, isReady, error } = useSQLiteWorker("https://raw.githubusercontent.com/microsoft/netperf/sqlite/netperf.sqlite");

  const [testData, setTestData] = useState(null);
  const [testData2, setTestData2] = useState(null);

  useEffect(() => {
    if (isReady) {
      console.log("Database is ready");
      exec("SELECT * FROM Environment", setTestData);
      exec("SELECT * FROM sqlite_master", setTestData2);
    }
  }, [isReady]);

  if (testData) {
    console.log("TEST DATA: ", testData);
  }

  if (testData2) {
    console.log("TEST DATA 2: ", testData2);
  }

  useScrollToTop();
 
  return (
    <ThemeProvider>
      <Router />
    </ThemeProvider>
  );
}
