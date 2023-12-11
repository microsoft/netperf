import React, { useState } from 'react';
import { Helmet } from 'react-helmet-async';

export default function DetailedPage(props) {
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
