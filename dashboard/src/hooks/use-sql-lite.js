import { useEffect, useState } from 'react';

const function_table = {};
let call_id = 0;


const useSQLiteWorker = (dbUrl) => {
  const [dbWorker, setDbWorker] = useState(null);
  const [isReady, setIsReady] = useState(false);
  const [db, setDb] = useState(null);
  const [err, setError] = useState(null);

  useEffect(() => {
    const devMode = false;
    let workerUrl = 'https://microsoft.github.io/netperf/wasm_worker.js' // DevURL = 'dist/wasm_worker.js'
    if (devMode) {
      workerUrl = 'dist/wasm_worker.js';
    }
    const worker = new Worker(workerUrl);
    worker.onmessage = (e) => {
      const { type, error, results, id } = e.data;
      switch (type) {
        case 'ready':
          setIsReady(true);
          setDb(results);
          break;
        case 'error':
          setError(error);
          break;
        case 'execResult':
          // Handle execution results here
          // console.log(function_table);
          function_table[id](results);
          break;
        default:
          break;
      }
    };

    worker.postMessage({ type: 'init', url: dbUrl });
    setDbWorker(worker);

    // Cleanup
    return () => {
      worker.terminate();
    };
  }, [dbUrl]);

  const exec = (sql, setState) => {

    call_id += 1;
    function_table[call_id] = setState;

    if (dbWorker && isReady) {
      dbWorker.postMessage({ type: 'exec', sql, call_id });
    } else {
      console.error('Database is not ready or worker is not set up');
    }
  };

  return { exec, isReady, db, err };
};

export default useSQLiteWorker;
