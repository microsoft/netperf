/* eslint-disable */
import { Helmet } from 'react-helmet-async';
import { useState, useEffect } from 'react';
import useSQLiteWorker from 'src/hooks/use-sql-lite';

// TODO: Make this more interesting :)
export default function DetailedPage(props) {

   const { exec, isReady, error } = useSQLiteWorker("https://raw.githubusercontent.com/microsoft/netperf/sqlite/netperf.sqlite");
   const [data, setData] = useState(null);

   useEffect(() => {
     console.log("Data: ", data);
   }, [data]);

   const [query, setQuery] = useState('');

   const executeQuery = (q) => {
      if (!isReady) {
         console.log("Database is not ready");
         return;
      }
      exec(q, setData);
   };

   const handleInputChange = (event) => {
      setQuery(event.target.value);
   };

   const handleQuerySubmit = () => {
      executeQuery(query);
   };

   return (
      <>
         <Helmet>
            <title> Detailed Page </title>
         </Helmet>

         <div>
            <input
               type="text"
               value={query}
               onChange={handleInputChange}
               placeholder="Enter SQL query"
            />
            <br />
            <button onClick={handleQuerySubmit}>Execute Query</button>
            {/* <button>Download sqlite file</button> */}
            <br />
            Look in the browser console for the full data output via inspect element.
            <br />
         </div>
      </>
   );
}
