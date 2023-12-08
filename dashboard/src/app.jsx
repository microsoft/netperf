/* eslint-disable perfectionist/sort-imports */
import 'src/global.css';

import { useScrollToTop } from 'src/hooks/use-scroll-to-top';

import useSQLite from './hooks/use-sql-lite';

import Router from 'src/routes/sections';
import ThemeProvider from 'src/theme';

// ----------------------------------------------------------------------

export default function App() {
  useScrollToTop();
  const { db, isLoading, error } = useSQLite("http://localhost:3030/netperf/dist/example.sqlite"); // TODO: replace with sqlite file from orphan branch.

  let content = <div className="spinner"></div>;
  
  if (error) {
    content = <div>Error...</div>
  } else if (db && !isLoading) {
    content = <Router db = {db} />
  }

  return (
    <ThemeProvider>
      {content}
    </ThemeProvider>
  );
}
