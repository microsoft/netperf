// Importing sql.js as a script inside the worker
importScripts('https://cdnjs.cloudflare.com/ajax/libs/sql.js/1.9.0/sql-wasm.js');

let db = null;
let ready = false;

onmessage = async (e) => {
  const { type, url } = e.data;

  switch (type) {
    case 'init':
      try {
        const SQL = await initSqlJs({
          locateFile: file => `https://cdnjs.cloudflare.com/ajax/libs/sql.js/1.9.0/${file}`
        });

        const response = await fetch(url);
        const buf = await response.arrayBuffer();
        db = new SQL.Database(new Uint8Array(buf));
        ready = true;
        postMessage({ type: 'ready' });
      } catch (err) {
        postMessage({ type: 'error', error: err.message });
      }
      break;
    case 'exec':
      if (db && ready) {
        const { sql, call_id } = e.data;
        try {
          const results = db.exec(sql);
          postMessage({ type: 'execResult', results, id: call_id });
        } catch (err) {
          postMessage({ type: 'error', error: err.message });
        }
      } else {
        postMessage({ type: 'error', error: 'Database not initialized' });
      }
      break;
    // Add more cases as needed for other operations
  }
};
