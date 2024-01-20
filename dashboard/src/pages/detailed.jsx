/* eslint-disable react-hooks/exhaustive-deps */
import { Helmet } from 'react-helmet-async';
import { useState, useEffect } from 'react';
import useSQLiteWorker from 'src/hooks/use-sql-lite';

export default function DetailedPage(props) {

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


   // const { db } = props;
   const [query, setQuery] = useState('');

   const executeQuery = (q) => {
      // const values = db.exec(q);
      // for (const val of values.values()) {
      //    console.log(val);
      // }
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
            {/* <button onClick={handleQuerySubmit}>Execute Query</button> */}
            {/* <button>Download sqlite file</button> */}
            <br />
            Look in the browser console for the output. (Right click, select option inspect element, navigate to the console tab)
            <br />
         </div>
      </>
   );
}
