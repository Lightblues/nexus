#!/usr/bin/env node
/**
 * Test script for get-windows package
 * Run: node scripts/test-get-windows.mjs
 */

import { activeWindow, activeWindowSync, openWindows } from 'get-windows'

async function main() {
  console.log('=== get-windows Test ===\n')

  // Test 1: Sync API
  console.log('1. Testing activeWindowSync()...')
  try {
    const syncResult = activeWindowSync()
    if (syncResult) {
      console.log('   ✓ Sync API works')
      console.log(`   App: ${syncResult.owner.name}`)
      console.log(`   Title: ${syncResult.title?.slice(0, 50)}...`)
    } else {
      console.log('   ⚠ No active window (this is OK if no window focused)')
    }
  } catch (err) {
    console.log(`   ✗ Sync API failed: ${err.message}`)
  }

  console.log()

  // Test 2: Async API
  console.log('2. Testing activeWindow()...')
  try {
    const asyncResult = await activeWindow()
    if (asyncResult) {
      console.log('   ✓ Async API works')
      console.log('   Full result:')
      console.log(JSON.stringify(asyncResult, null, 2).split('\n').map(l => '   ' + l).join('\n'))
    } else {
      console.log('   ⚠ No active window')
    }
  } catch (err) {
    console.log(`   ✗ Async API failed: ${err.message}`)
  }

  console.log()

  // Test 3: Open windows list
  console.log('3. Testing openWindows()...')
  try {
    const windows = await openWindows()
    console.log(`   ✓ Found ${windows.length} open windows`)
    console.log('   Top 5 windows:')
    windows.slice(0, 5).forEach((w, i) => {
      console.log(`   ${i + 1}. ${w.owner.name} - ${w.title?.slice(0, 40)}...`)
    })
  } catch (err) {
    console.log(`   ✗ openWindows failed: ${err.message}`)
  }

  console.log()

  // Test 4: Check URL retrieval (browser only)
  console.log('4. Checking URL field availability...')
  try {
    const win = await activeWindow()
    if (win?.url) {
      console.log(`   ✓ URL available: ${win.url}`)
    } else if (win?.owner.name.includes('Chrome') || win?.owner.name.includes('Safari')) {
      console.log('   ⚠ Browser detected but no URL (may need accessibility permission)')
    } else {
      console.log('   ℹ Current app is not a browser, URL field not applicable')
    }
  } catch (err) {
    console.log(`   ✗ Error: ${err.message}`)
  }

  console.log('\n=== Test Complete ===')
}

main().catch(console.error)
