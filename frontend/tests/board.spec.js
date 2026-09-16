import { test, expect } from '@playwright/test'

test.describe('task board rendered acceptance', () => {
  test('opens the board and task detail with independent scrolling', async ({ page }) => {
    await page.goto('/tasks')
    await expect(page.getByText('Task board', { exact: true })).toBeVisible()
    await expect(page.getByTestId('task-board')).toBeVisible()

    const firstCard = page.getByTestId('task-card').first()
    await expect(firstCard).toBeVisible()
    await firstCard.click()
    await expect(page.getByRole('complementary', { name: 'Task details' })).toBeVisible()

    const board = page.getByTestId('task-board')
    const detail = page.getByRole('complementary', { name: 'Task details' })
    expect(await board.evaluate((node) => ['auto', 'scroll'].includes(getComputedStyle(node).overflowY))).toBeTruthy()
    expect(await detail.evaluate((node) => ['auto', 'scroll'].includes(getComputedStyle(node).overflowY))).toBeTruthy()
    const boardScrolls = await board.evaluate((node) => { node.scrollTop = 120; return node.scrollTop })
    const detailScrolls = await detail.evaluate((node) => { node.scrollTop = 120; return node.scrollTop })
    expect(boardScrolls).toBeGreaterThanOrEqual(0)
    expect(detailScrolls).toBeGreaterThanOrEqual(0)
    await page.screenshot({ path: 'test-results/board-detail-desktop.png', fullPage: true })
  })

  test('creates a task and exercises narrow layout', async ({ page }) => {
    await page.goto('/tasks')
    await expect(page.getByTestId('task-card').first()).toBeVisible()
    await page.getByRole('button', { name: '+ New task' }).click()
    const createForm = page.locator('.create-bar form')
    await expect(createForm).toBeVisible()
    const title = `Playwright task ${Date.now()}`
    await createForm.locator('input[placeholder="What needs doing?"]').fill(title)
    await createForm.locator('select').first().selectOption('runtime-project')
    const createResponse = page.waitForResponse((response) => response.url().includes('/api/projects/') && response.request().method() === 'POST')
    await page.getByRole('button', { name: 'Create task', exact: true }).click()
    expect((await createResponse).status()).toBe(201)
    await expect(page.getByTestId('task-card').filter({ hasText: title })).toBeVisible()
    await page.screenshot({ path: 'test-results/task-created.png', fullPage: true })
  })

  test('drags within a column while remaining visually stable', async ({ page }) => {
    await page.goto('/tasks')
    const source = page.getByTestId('board-column-backlog').getByTestId('task-card').nth(1)
    const target = page.getByTestId('board-column-backlog').getByTestId('task-card').nth(3)
    await source.dragTo(target, { targetPosition: { x: 80, y: 12 } })
    expect(await page.getByTestId('board-column-backlog').getByTestId('task-card').count()).toBeGreaterThan(1)
    await page.screenshot({ path: 'test-results/drag-within-column.png', fullPage: true })
  })

  test('drags between columns while remaining visually stable', async ({ page }) => {
    await page.goto('/tasks')
    const source = page.getByTestId('board-column-backlog').getByTestId('task-card').first()
    const destination = page.getByTestId('board-column-ready')
    await expect(source).toBeVisible()

    const before = await page.getByTestId('board-column-backlog').getByTestId('task-card').allTextContents()
    await source.dragTo(destination, { targetPosition: { x: 80, y: 110 } })
    await expect(page.getByTestId('board-column-ready').getByTestId('task-card').filter({ hasText: before[0].split('\n')[0] })).toBeVisible()
    await page.screenshot({ path: 'test-results/drag-between-columns.png', fullPage: true })
  })

  test('keeps the provisional insertion index stable when hit targets alternate', async ({ page }) => {
    await page.goto('/tasks')
    const lane = page.getByTestId('board-column-backlog')
    const cards = lane.getByTestId('task-card')
    await expect(cards.nth(2)).toBeVisible()
    await page.evaluate(() => { window.__LB_DRAG_TRACE__ = true; window.__LB_DRAG_EVENTS__ = [] })

    const pointerY = await cards.nth(2).evaluate((card) => {
      const box = card.getBoundingClientRect()
      return box.top + box.height / 2
    })
    const changes = await page.evaluate((y) => {
      const laneCards = [...document.querySelectorAll('[data-testid="board-column-backlog"] [data-testid="task-card"]')]
      const dataTransfer = new DataTransfer()
      laneCards[0].dispatchEvent(new DragEvent('dragstart', { bubbles: true, dataTransfer }))
      for (const index of [1, 2, 3, 1, 2, 3]) {
        laneCards[index].dispatchEvent(new DragEvent('dragover', { bubbles: true, clientY: y, dataTransfer }))
      }
      return window.__LB_DRAG_EVENTS__.filter((event) => event.handler === 'provisional-change')
    }, pointerY)
    expect(changes.length).toBeGreaterThan(0)
    expect(new Set(changes.map((event) => event.candidateIndex)).size).toBe(1)
    await cards.first().dispatchEvent('dragend')
  })
})
