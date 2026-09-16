import { defineConfig, devices } from '@playwright/test'

export default defineConfig({
  testDir: './tests',
  outputDir: './test-results',
  fullyParallel: false,
  retries: process.env.CI ? 2 : 0,
  reporter: process.env.CI ? 'github' : 'list',
  use: {
    baseURL: 'http://127.0.0.1:5173',
    trace: 'retain-on-failure',
    video: 'retain-on-failure',
    screenshot: 'only-on-failure',
  },
  projects: [
    { name: 'setup', testMatch: /auth\.setup\.js/, use: { storageState: undefined } },
    { name: 'chromium', dependencies: ['setup'], use: { ...devices['Desktop Chrome'], storageState: 'playwright/.auth/user.json' } },
    { name: 'tablet', dependencies: ['setup'], use: { ...devices['Desktop Chrome'], viewport: { width: 768, height: 1024 }, storageState: 'playwright/.auth/user.json' } },
  ],
  webServer: [
    {
      command: 'cd ../backend && DISABLE_SEARCH_INDEXING=true bin/rails server -p 3100 -b 127.0.0.1',
      url: 'http://127.0.0.1:3100/up',
      reuseExistingServer: !process.env.CI,
      timeout: 120_000,
    },
    {
      command: 'VITE_API_BASE_URL=/ npm run dev -- --host 127.0.0.1 --port 5173',
      url: 'http://127.0.0.1:5173',
      reuseExistingServer: !process.env.CI,
      timeout: 120_000,
    },
  ],
})
