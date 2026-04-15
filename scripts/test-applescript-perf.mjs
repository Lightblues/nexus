#!/usr/bin/env node
/**
 * AppleScript performance test for window tracking
 * Compares AppleScript vs get-windows performance
 * Run: node scripts/test-applescript-perf.mjs
 */

import { execFile } from 'child_process'
import { promisify } from 'util'

const execFileAsync = promisify(execFile)

const POLL_INTERVAL = 2000
const MAX_POLLS = 10
const BENCHMARK_ROUNDS = 20

// AppleScript to get active window info
const APPLESCRIPT = `
tell application "System Events"
  set frontApp to first application process whose frontmost is true
  set appName to name of frontApp
  set bundleId to bundle identifier of frontApp

  -- Get window title
  try
    set winTitle to name of front window of frontApp
  on error
    set winTitle to ""
  end try

  -- Get display name (localized app name)
  try
    set displayName to displayed name of frontApp
  on error
    set displayName to appName
  end try

  return appName & "|||" & bundleId & "|||" & winTitle & "|||" & displayName
end tell
`

// Browser URL scripts
const CHROME_URL_SCRIPT = `tell application "Google Chrome" to return URL of active tab of front window`
const SAFARI_URL_SCRIPT = `tell application "Safari" to return URL of front document`
const ARC_URL_SCRIPT = `tell application "Arc" to return URL of active tab of front window`

async function getWindowAppleScript() {
  const start = performance.now()
  try {
    const { stdout } = await execFileAsync('osascript', ['-e', APPLESCRIPT], { timeout: 3000 })
    const elapsed = performance.now() - start
    const parts = stdout.trim().split('|||')
    return {
      app: parts[0],
      bundleId: parts[1] || undefined,
      title: parts[2] || undefined,
      displayName: parts[3] || parts[0],
      elapsed
    }
  } catch (err) {
    return { error: err.message, elapsed: performance.now() - start }
  }
}

async function getBrowserUrl(bundleId) {
  if (!bundleId) return null
  let script

  if (bundleId.includes('chrome') || bundleId.includes('Chrome')) {
    script = CHROME_URL_SCRIPT
  } else if (bundleId.includes('safari') || bundleId === 'com.apple.Safari') {
    script = SAFARI_URL_SCRIPT
  } else if (bundleId.includes('Browser') || bundleId.includes('Arc') || bundleId.includes('antigravity')) {
    script = ARC_URL_SCRIPT
  }

  if (!script) return null

  const start = performance.now()
  try {
    const { stdout } = await execFileAsync('osascript', ['-e', script], { timeout: 2000 })
    return { url: stdout.trim(), elapsed: performance.now() - start }
  } catch (err) {
    return { url: null, error: err.message, elapsed: performance.now() - start }
  }
}

async function getWindowGetWindows() {
  const start = performance.now()
  try {
    const { activeWindow } = await import('get-windows')
    const win = await activeWindow({ screenRecordingPermission: false })
    const elapsed = performance.now() - start
    return win ? { ...win, elapsed } : { error: 'No window', elapsed }
  } catch (err) {
    return { error: err.message, elapsed: performance.now() - start }
  }
}

async function benchmark() {
  console.log('=== Performance Benchmark ===')
  console.log(`Running ${BENCHMARK_ROUNDS} rounds each...\n`)

  const appleScriptTimes = []
  const getWindowsTimes = []

  for (let i = 0; i < BENCHMARK_ROUNDS; i++) {
    const as = await getWindowAppleScript()
    appleScriptTimes.push(as.elapsed)

    const gw = await getWindowGetWindows()
    getWindowsTimes.push(gw.elapsed)

    process.stdout.write(`\rRound ${i + 1}/${BENCHMARK_ROUNDS}`)
  }
  console.log('\n')

  const avg = arr => arr.reduce((a, b) => a + b, 0) / arr.length
  const min = arr => Math.min(...arr)
  const max = arr => Math.max(...arr)

  console.log('Method            | Avg(ms) | Min(ms) | Max(ms)')
  console.log('------------------|---------|---------|--------')
  console.log(`AppleScript       | ${avg(appleScriptTimes).toFixed(1).padStart(7)} | ${min(appleScriptTimes).toFixed(1).padStart(7)} | ${max(appleScriptTimes).toFixed(1).padStart(6)}`)
  console.log(`get-windows       | ${avg(getWindowsTimes).toFixed(1).padStart(7)} | ${min(getWindowsTimes).toFixed(1).padStart(7)} | ${max(getWindowsTimes).toFixed(1).padStart(6)}`)
  console.log('')
}

async function poll() {
  const win = await getWindowAppleScript()
  if (win.error) {
    console.log(`[Error] ${win.error} (${win.elapsed.toFixed(1)}ms)`)
    return
  }

  const ts = new Date().toLocaleTimeString()
  const app = win.app
  const displayName = win.displayName

  console.log(`\n[${ts}] ${displayName} (${win.elapsed.toFixed(1)}ms)`)
  console.log(`  Process: ${app}`)
  console.log(`  Bundle: ${win.bundleId || 'N/A'}`)

  // Identify app by bundle ID or name
  const bundleId = win.bundleId || ''
  const isBrowser = bundleId.includes('chrome') || bundleId.includes('Chrome') ||
                    bundleId.includes('safari') || bundleId.includes('Safari') ||
                    bundleId.includes('firefox') || bundleId.includes('Firefox') ||
                    bundleId.includes('Browser') || bundleId.includes('Arc') ||
                    app.includes('Chrome') || app.includes('Safari') || app.includes('Firefox') || app.includes('Arc')

  const isVSCode = bundleId.includes('VSCode') || bundleId.includes('Code') || app.includes('Code')

  if (isBrowser) {
    const urlResult = await getBrowserUrl(win.bundleId)
    if (urlResult) {
      console.log(`  URL: ${urlResult.url || '(failed)'} (${urlResult.elapsed.toFixed(1)}ms)`)
    }
    console.log(`  Title: ${win.title?.slice(0, 60) || '(empty)'}`)
  } else if (isVSCode) {
    const parts = win.title?.split(' — ') || []
    const project = parts[parts.length - 1] || '(unknown)'
    const file = parts[0] || '(unknown)'
    console.log(`  File: ${file}`)
    console.log(`  Project: ${project}`)
    console.log(`  Title: ${win.title?.slice(0, 80) || '(empty)'}`)
  } else {
    console.log(`  Title: ${win.title?.slice(0, 60) || '(empty)'}`)
  }
}

async function main() {
  const args = process.argv.slice(2)

  if (args.includes('--benchmark') || args.includes('-b')) {
    await benchmark()
    return
  }

  console.log('=== AppleScript Window Test ===')
  console.log(`Polling every ${POLL_INTERVAL / 1000}s for ${MAX_POLLS} times...`)
  console.log('Use --benchmark or -b to run performance comparison.\n')

  for (let i = 0; i < MAX_POLLS; i++) {
    try {
      await poll()
    } catch (err) {
      console.log(`Error: ${err.message}`)
    }
    if (i < MAX_POLLS - 1) {
      await new Promise(r => setTimeout(r, POLL_INTERVAL))
    }
  }
  console.log('\n=== Done ===')
}

main().catch(console.error)
