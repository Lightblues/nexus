#!/usr/bin/env node
/**
 * Test script for @paymoapp/active-window
 * Run: node scripts/test-paymo-active-window.mjs
 *
 * Focus: Chrome (URL) and VSCode (project)
 */

import pkg from '@paymoapp/active-window'
const { ActiveWindow } = pkg

const POLL_INTERVAL = 2000
const MAX_POLLS = 15

function parseVSCodeProject(title) {
  if (!title) return null
  const parts = title.split(' — ')
  return parts[parts.length - 1] || null
}

function main() {
  console.log('=== @paymoapp/active-window Test ===\n')

  // Initialize
  ActiveWindow.initialize()

  // Check permissions
  console.log('Checking permissions...')
  const hasPermission = ActiveWindow.requestPermissions()
  if (!hasPermission) {
    console.log('⚠ Screen Recording permission required!')
    console.log('  → System Preferences > Security & Privacy > Privacy > Screen Recording')
    console.log('  (Continuing anyway, but title may be empty)\n')
  } else {
    console.log('✓ Permissions OK\n')
  }

  console.log(`Polling every ${POLL_INTERVAL/1000}s for ${MAX_POLLS} times...`)
  console.log('Switch between Chrome and VSCode to test.\n')

  let count = 0
  const interval = setInterval(() => {
    try {
      const win = ActiveWindow.getActiveWindow()
      const ts = new Date().toLocaleTimeString()

      if (!win) {
        console.log(`[${ts}] No active window`)
      } else {
        const app = win.application
        console.log(`\n[${ts}] ${app}`)
        console.log(`  PID: ${win.pid}`)
        console.log(`  Path: ${win.path}`)

        if (app.includes('Chrome') || app.includes('Safari') || app.includes('Firefox') || app.includes('Arc')) {
          console.log(`  🌐 Title: ${win.title?.slice(0, 80) || '(empty - need permission)'}`)
          // Note: @paymoapp/active-window doesn't provide URL directly
          console.log(`  ℹ URL: (not available in this package, need AppleScript)`)
        } else if (app.includes('Code')) {
          const project = parseVSCodeProject(win.title)
          console.log(`  📁 Project: ${project || '(unknown)'}`)
          console.log(`  📄 Title: ${win.title?.slice(0, 60) || '(empty)'}`)
        } else {
          console.log(`  📄 Title: ${win.title?.slice(0, 60) || '(empty)'}`)
        }
      }
    } catch (err) {
      console.log(`Error: ${err.message}`)
    }

    count++
    if (count >= MAX_POLLS) {
      clearInterval(interval)
      console.log('\n=== Done ===')
      process.exit(0)
    }
  }, POLL_INTERVAL)
}

main()
