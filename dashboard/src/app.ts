import express, { Request, Response } from 'express'
import path from 'path'
import { dirname } from 'path';

const app = express();
const __dirname__ = dirname('dist');

app.use(express.static(path.join('dist')));

// Add API routes here to query database data.

app.get('/hello', (_, res) => {
  res.send('Hello World!');
});

app.use((_req: Request, res: Response) => {
  return res.sendFile(path.resolve(__dirname__, 'dist', 'index.html'));
});

app.listen(process.env.PORT || 5000, () => {
  console.log('Server running on port ' + (process.env.PORT || 5000));
});
