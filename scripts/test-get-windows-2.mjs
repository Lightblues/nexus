#!/usr/bin/env node
/**
 * Minimal active-window test for Chrome (URL) and VSCode (project)
 * Run: node scripts/test-active-window.mjs
 *
 * Instructions: Switch to Chrome or VSCode, then run this script
 */

import { activeWindow } from 'get-windows'

const POLL_INTERVAL = 2000
const MAX_POLLS = 15

function parseVSCodeProject(title) {
  // Title format: "filename — project" or "project"
  if (!title) return null
  const parts = title.split(' — ')
  // Last part is typically the project name (or the only part)
  return parts[parts.length - 1] || null
}

function parseChromeInfo(win) {
  return {
    url: win.url || '(no url - need accessibility permission)',
    title: win.title || '(no title - need screen recording permission)'
  }
}

async function poll() {
  const win = await activeWindow()
  if (!win) {
    console.log('[No active window]')
    return
  }

  const app = win.owner.name
  const ts = new Date().toLocaleTimeString()

  console.log(`\n[${ts}] ${app}`)
  console.log(`  PID: ${win.owner.processId}, Bundle: ${win.owner.bundleId || 'N/A'}`)

  if (app.includes('Chrome') || app.includes('Safari') || app.includes('Firefox') || app.includes('Arc')) {
    const info = parseChromeInfo(win)
    console.log(`  🌐 URL: ${info.url}`)
    console.log(`  📄 Title: ${info.title.slice(0, 60)}`)
  } else if (app.includes('Code')) {
    const project = parseVSCodeProject(win.title)
    console.log(`  📁 Project: ${project || '(unknown)'}`)
    console.log(`  📄 Title: ${win.title?.slice(0, 60) || '(empty)'}`)
  } else {
    console.log(`  📄 Title: ${win.title?.slice(0, 60) || '(empty)'}`)
  }
}

async function main() {
  console.log('=== Active Window Test (Chrome URL / VSCode Project) ===')
  console.log(`Polling every ${POLL_INTERVAL/1000}s for ${MAX_POLLS} times...`)
  console.log('Switch between Chrome and VSCode to test.\n')

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
