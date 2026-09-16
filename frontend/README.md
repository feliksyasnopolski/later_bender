# Later, Bender frontend

Run the rendered browser acceptance suite locally with a development Rails API:

```sh
PLAYWRIGHT_USERNAME=local-development \
PLAYWRIGHT_PASSWORD='your local password' \
npm run test:e2e
```

The suite starts Rails on port 3100 with optional search indexing disabled and Vite on port 5173. It authenticates once into a local Playwright storage state, then exercises desktop and 768px tablet Chromium flows. Use `npm run test:e2e:headed` to watch the browser. Screenshots, videos, and traces are written to `test-results/` and are intentionally local debugging evidence.
