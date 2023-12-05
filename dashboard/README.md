## Quick Start

Make sure you install Node.js on your system.

- cd /dashboard
- npm i
- npm run dev (starts local server)

## Building for production:
- npm run build
    - This will automatically configure everything to assume the root url is `netperf/dist` instead of `/`, for the sake of Github Pages.
    - A /dist folder will appear that contains the raw HTML, JS, CSS... etc.
