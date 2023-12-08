import initSqlJs from 'sql.js'

const sqlPromise = initSqlJs({
    locateFile: file => `https://cdnjs.cloudflare.com/ajax/libs/sql.js/1.9.0/${file}`
});

const dataPromise = fetch("http://localhost:3030/netperf/dist/example.sqlite").then(res => res.arrayBuffer()); // TODO: replace this with netperf/sqlite URL.
const [SQL, buf] = await Promise.all([sqlPromise, dataPromise])
const db = new SQL.Database(new Uint8Array(buf));

export default db