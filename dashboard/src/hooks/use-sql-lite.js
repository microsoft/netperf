import initSqlJs from 'sql.js';
import { useState, useEffect } from 'react';


const useSQLite = (dbUrl) => {
  const [db, setDb] = useState(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState(null);

  useEffect(() => {
    let dbInstance = null;

    const loadDatabase = async () => {
      try {
        const SQL = await initSqlJs({
          locateFile: file => `https://cdnjs.cloudflare.com/ajax/libs/sql.js/1.9.0/${file}`
        });

        const response = await fetch(dbUrl);
        const buf = await response.arrayBuffer();
        dbInstance = new SQL.Database(new Uint8Array(buf));
        setDb(dbInstance);
      } catch (err) {
        setError(err);
      } finally {
        setLoading(false);
      }
    };

    loadDatabase();

    // Cleanup function to close the db when the component unmounts
    return () => {
      if (dbInstance) {
        dbInstance.close();
      }
    };
  }, [dbUrl]);

  return { db, loading, error };
};

export default useSQLite;
