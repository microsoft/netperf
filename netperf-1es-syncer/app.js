import express from 'express';
import dotenv from 'dotenv';
dotenv.config();

const app = express();
const state = {};
const keyCreationTime = {};

function cleanup(runid) {
    const currentTime = new Date().getTime();
    for (const key in keyCreationTime) {
        // Keys created over 3 days ago need to be deleted
        if (currentTime - keyCreationTime[key] > 3 * 24 * 60 * 60 * 1000) {
            delete state[key];
            delete keyCreationTime[key];
        }
        // If key has run id as a substring, delete it
        if (key.includes(runid)) {
            delete state[key];
            delete keyCreationTime[key];
        }
    }
}

// Middleware to parse JSON
app.use(express.json());

app.get('/', (_, res) => {
    res.send('Hello World');
});

app.get('/hello', (req, res) => {
    const secret = req.headers.secret;
    if (!secret || secret !== process.env.SECRET) {
        return res.status(400).send('Bad Request.');
    }
    res.send('Hello World');
});

app.post('/setkeyvalue', (req, res) => {
    const key = req.query.key;
    const value = req.query.value;
    const valueFromBody = req.body.value;
    const secret = req.headers.secret;
    if (!key || !secret || secret !== process.env.SECRET) {
        return res.status(400).send('Bad Request.');
    }
    if (!value && !valueFromBody) {
        return res.status(400).send('Bad Request. Missing value.');
    }
    if (valueFromBody) {
        state[key] = valueFromBody;
        // Set expiration time to be 30 minutes from now
        keyCreationTime[key] = new Date().getTime();
        res.send('Data has been synced from body');
    } else {
        state[key] = value;
        // Set expiration time to be 1 minutes from now
        keyCreationTime[key] = new Date().getTime();
        res.send('Data has been synced from url params');
    }
});

app.get('/getkeyvalue', (req, res) => {
    const key = req.query.key;
    const secret = req.headers.secret;
    if (!key || !secret || secret !== process.env.SECRET) {
        return res.status(400).send('Bad Request.');
    }
    if (!state.hasOwnProperty(key)) {
        return res.status(404).send('Data not found');
    }
    res.send(state[key]);
});

app.get('/cleanuprun', (req, res) => {
    const runid = req.query.runid;
    const secret = req.headers.secret;
    if (!secret || secret !== process.env.SECRET || !runid) {
        return res.status(400).send('Bad Request.');
    }
    cleanup(runid);
    res.send('Cleanup run successfully');
});

const port = process.env.PORT || 8080;
app.listen(port, () => {
  console.log('Server is running on port 8080');
});
