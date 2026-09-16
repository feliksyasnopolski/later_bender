import { test as setup, expect } from '@playwright/test'

const authFile = 'playwright/.auth/user.json'

setup('authenticate', async ({ page }) => {
  const username = process.env.PLAYWRIGHT_USERNAME
  const password = process.env.PLAYWRIGHT_PASSWORD
  if (!username || !password) throw new Error('Set PLAYWRIGHT_USERNAME and PLAYWRIGHT_PASSWORD to run the browser acceptance suite.')

  await page.goto('/login')
  await page.getByLabel('Username').fill(username)
  await page.getByLabel('Password').fill(password)
  await page.getByRole('button', { name: 'Log in' }).click()
  await expect(page).toHaveURL(/\/projects|\/tasks/)
  await page.context().storageState({ path: authFile })
})
