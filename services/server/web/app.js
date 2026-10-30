// Read-only views of the server's day summaries. Every page is a URL: /app, /app/day/<day>, /app/day/<day>/records, /app/history, /app/devices.

const COLORS = {
  coding: '#4f7cff', ai: '#9b6bff', communication: '#20b2aa', meeting: '#f59e0b', notes: '#22c55e',
  reading: '#14b8a6', entertainment: '#ef4444', browsing: '#64748b', system: '#94a3b8', other: '#cbd5e1',
}
const view = document.getElementById('view')
let me = null

const esc = s => String(s ?? '').replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]))
const color = c => COLORS[c] ?? COLORS.other

function hours(seconds) {
  if (!seconds) return '0m'
  const h = Math.floor(seconds / 3600), m = Math.round((seconds % 3600) / 60)
  return h ? `${h}h ${String(m).padStart(2, '0')}m` : `${m}m`
}
const timeFmt = () => new Intl.DateTimeFormat(undefined, { timeZone: me.tz, hour: '2-digit', minute: '2-digit', hourCycle: 'h23' })
const stampFmt = () => new Intl.DateTimeFormat(undefined, { timeZone: me.tz, dateStyle: 'medium', timeStyle: 'medium' })
const time = s => s == null ? '—' : `<time title="${esc(stampFmt().format(s * 1000))}">${timeFmt().format(s * 1000)}</time>`
const stamp = ms => ms == null ? '—' : `<time title="${esc(new Date(ms).toISOString())}">${stampFmt().format(ms)}</time>`
function shift(day, by) {
  const [y, m, d] = day.split('-').map(Number)
  return new Date(Date.UTC(y, m - 1, d + by)).toISOString().slice(0, 10)
}
const weekday = day => new Date(`${day}T12:00:00Z`).toLocaleDateString(undefined, { weekday: 'short', timeZone: 'UTC' })

async function api(path) {
  const res = await fetch(path, { credentials: 'same-origin' })
  if (res.status === 401) { location.href = '/login'; throw new Error('signed out') }
  if (!res.ok) throw new Error(`${res.status} ${(await res.json().catch(() => ({}))).error?.message ?? ''}`)
  return res.json()
}

function crumbs(parts) {
  document.getElementById('crumbs').innerHTML = [['Nexus', '/app'], ...parts]
    .map(([label, href], i, all) => i === all.length - 1 ? `<span>${esc(label)}</span>` : `<a href="${href}">${esc(label)}</a>`)
    .join('<span class="sep">/</span>')
  document.title = parts.length ? `${parts.at(-1)[0]} · Nexus` : 'Nexus'
}

function tab(name) {
  for (const a of document.querySelectorAll('.tabs a')) a.classList.toggle('active', a.dataset.tab === name)
}

function bars(all, label, total) {
  const rows = all.filter(r => r.seconds >= 60)
  if (!rows.length) return '<p class="muted">Nothing recorded.</p>'
  const max = Math.max(...rows.map(r => r.seconds))
  return `<ul class="bars">${rows.map(r => `
    <li><span class="label" title="${esc(r[label])}">${r.category ? `<i class="dot" style="background:${color(r.category)}"></i>` : ''}${esc(r[label])}</span>
      <span class="track"><span style="width:${(r.seconds / max * 100).toFixed(1)}%;background:${color(r.category ?? 'coding')}"></span></span>
      <span class="value">${hours(r.seconds)}${total ? ` <small>${Math.round(r.seconds / total * 100)}%</small>` : ''}</span></li>`).join('')}</ul>`
}

/** 24 h strip: blocks by category, pomodoro work sessions as a row beneath. */
function timeline(s, from) {
  const pos = t => ((t - from) / 86400 * 100).toFixed(2)
  const width = (a, b) => Math.max(0.15, (b - a) / 86400 * 100).toFixed(2)
  const blocks = s.blocks.map(b => `<span class="seg" style="left:${pos(b.start)}%;width:${width(b.start, b.end)}%;background:${color(b.category)}" title="${esc(`${timeFmt().format(b.start * 1000)}–${timeFmt().format(b.end * 1000)} ${b.category} · ${b.label} · ${hours(b.seconds)}`)}"></span>`).join('')
  const pomos = s.pomodoro.sessions.filter(p => p.kind === 'work').map(p => `<span class="seg pomo" style="left:${pos(p.start)}%;width:${width(p.start, p.end)}%" title="${esc(`${timeFmt().format(p.start * 1000)} ${p.project ?? ''} ${p.task ?? ''}`)}"></span>`).join('')
  const ticks = [0, 6, 12, 18, 24].map(h => `<span class="tick" style="left:${h / 24 * 100}%">${String(h).padStart(2, '0')}</span>`).join('')
  return `<div class="timeline"><div class="lane">${blocks}</div><div class="lane thin">${pomos}</div><div class="ticks">${ticks}</div></div>`
}

/** Local midnight of `day` in the server's zone. */
function midnight(day) {
  const guess = Date.parse(`${day}T00:00:00Z`) / 1000
  const parts = Object.fromEntries(new Intl.DateTimeFormat('en-US', { timeZone: me.tz, hourCycle: 'h23', year: 'numeric', month: '2-digit', day: '2-digit', hour: '2-digit', minute: '2-digit' })
    .formatToParts(guess * 1000).filter(p => p.type !== 'literal').map(p => [p.type, Number(p.value)]))
  const asUTC = Date.UTC(parts.year, parts.month - 1, parts.day, parts.hour, parts.minute) / 1000
  return guess - (asUTC - guess)
}

async function dayPage(day) {
  const isToday = day === me.today
  tab(isToday ? 'today' : 'history')
  crumbs(isToday ? [[`Today · ${day}`]] : [['History', '/app/history'], [day]])
  const s = await api(`/api/days/${day}`)
  const p = s.pomodoro
  view.innerHTML = `
    <div class="pager"><a href="/app/day/${shift(day, -1)}">← ${shift(day, -1)}</a><h1>${esc(weekday(day))} ${day}</h1>${isToday ? '<span></span>' : `<a href="/app/day/${shift(day, 1)}">${shift(day, 1)} →</a>`}</div>
    <section class="cards">
      <div><b>${hours(s.activeSeconds)}</b><span>active</span></div>
      <div><b>${p.work}</b><span>pomodoros · ${hours(p.workSeconds)}</span></div>
      <div><b>${time(s.first)}–${time(s.last)}</b><span>first – last</span></div>
      <div><b>${s.devices.length}</b><span>${s.devices.length === 1 ? 'Mac' : 'Macs'}</span></div>
    </section>
    <section><h2>Timeline</h2>${timeline(s, midnight(day))}
      <ul class="legend">${s.categories.map(c => `<li><i class="dot" style="background:${color(c.category)}"></i>${esc(c.category)}</li>`).join('')}<li><i class="dot pomo"></i>pomodoro</li></ul></section>
    <div class="grid">
      <section><h2>Categories</h2>${bars(s.categories, 'category', s.activeSeconds)}</section>
      <section><h2>Projects</h2>${bars(s.projects, 'project')}</section>
      <section><h2>Apps</h2>${bars(s.apps, 'app')}</section>
      <section><h2>Sites</h2>${bars(s.domains, 'domain')}</section>
    </div>
    <section><h2>Focus blocks</h2>${s.blocks.length ? `<table><tr><th>Time</th><th>Category</th><th>Mostly</th><th>Length</th></tr>${s.blocks.map(b => `
      <tr><td>${time(b.start)}–${time(b.end)}</td><td><i class="dot" style="background:${color(b.category)}"></i>${esc(b.category)}</td><td>${esc(b.label)}</td><td>${hours(b.seconds)}</td></tr>`).join('')}</table>` : '<p class="muted">No stretch of 10 minutes or more.</p>'}</section>
    <section><h2>Pomodoros</h2>${p.sessions.length ? `<table><tr><th>Time</th><th>Kind</th><th>Project</th><th>Task</th><th></th></tr>${p.sessions.map(x => `
      <tr><td>${time(x.start)}–${time(x.end)}</td><td>${esc(x.kind)}</td><td>${esc(x.project ?? '')}</td><td>${esc(x.task ?? '')}</td><td>${x.completed ? '✓' : ''}</td></tr>`).join('')}</table>` : '<p class="muted">No sessions.</p>'}</section>
    <p><a href="/app/day/${day}/records">All activity rows for ${day} →</a></p>`
}

async function recordsPage(day) {
  tab(day === me.today ? 'today' : 'history')
  crumbs(day === me.today ? [[`Today · ${day}`, '/app'], ['Rows']] : [['History', '/app/history'], [day, `/app/day/${day}`], ['Rows']])
  const { activities } = await api(`/api/days/${day}/records`)
  view.innerHTML = `<h1>Activity rows · ${day}</h1>
    <p class="muted">${activities.length} rows after cleaning (lock screen dropped, rows over an hour capped). Times in ${esc(me.tz)}.</p>
    <div class="scroll"><table class="rows"><tr><th>Start</th><th>Length</th><th>Category</th><th>App</th><th>Project / site</th><th>Title</th><th>Mac</th></tr>
    ${activities.map(a => `<tr><td>${time(a.start)}</td><td>${hours(a.seconds)}</td><td><i class="dot" style="background:${color(a.category)}"></i>${esc(a.category)}</td>
      <td title="${esc(a.bundleId ?? '')}">${esc(a.app)}</td><td>${esc(a.project ?? a.domain ?? '')}</td><td class="title" title="${esc(a.url ?? a.title ?? '')}">${esc(a.file ?? a.title ?? '')}</td>
      <td><code title="${esc(a.device)}">${esc(a.device.slice(0, 8))}</code></td></tr>`).join('')}</table></div>`
}

async function historyPage() {
  tab('history')
  crumbs([['History']])
  const q = new URLSearchParams(location.search)
  const to = q.get('to') || me.today, from = q.get('from') || shift(to, -29)
  const { days } = await api(`/api/days?from=${from}&to=${to}`)
  const byDay = new Map(days.map(d => [d.day, d]))
  const max = Math.max(3600, ...days.map(d => d.activeSeconds))
  const rows = []
  for (let d = to; d >= from; d = shift(d, -1)) {
    const s = byDay.get(d)
    const segs = s ? s.categories.map(c => `<span style="width:${(c.seconds / max * 100).toFixed(2)}%;background:${color(c.category)}" title="${esc(`${c.category} ${hours(c.seconds)}`)}"></span>`).join('') : ''
    rows.push(`<tr><td><a href="/app/day/${d}">${d}</a> <small class="muted">${esc(weekday(d))}</small></td><td>${s ? hours(s.activeSeconds) : '—'}</td><td>${s?.pomodoro.work || ''}</td><td class="stack">${segs}</td></tr>`)
  }
  const total = days.reduce((n, d) => n + d.activeSeconds, 0), pomos = days.reduce((n, d) => n + d.pomodoro.work, 0)
  view.innerHTML = `<div class="pager"><a href="/app/history?to=${shift(from, -1)}">← earlier</a><h1>${from} – ${to}</h1>${to < me.today ? `<a href="/app/history?to=${shift(to, 30) > me.today ? me.today : shift(to, 30)}">later →</a>` : '<span></span>'}</div>
    <section class="cards"><div><b>${hours(total)}</b><span>active</span></div><div><b>${pomos}</b><span>pomodoros</span></div><div><b>${days.filter(d => d.activeSeconds).length}</b><span>tracked days</span></div></section>
    <table class="history"><tr><th>Day</th><th>Active</th><th>Pomos</th><th>By category</th></tr>${rows.join('')}</table>`
}

async function devicesPage() {
  tab('devices')
  crumbs([['Devices']])
  const { devices } = await api('/api/devices')
  view.innerHTML = `<h1>Devices</h1>
    <p class="muted">Every Mac (and the CLI) that pushed with this key. Signed in as <b>${esc(me.name)}</b> (<code>${esc(me.user)}</code>, ${esc(me.access)}), days in ${esc(me.tz)}.</p>
    <div class="scroll"><table><tr><th>Name</th><th>Device id</th><th>Last push</th><th>Last activity</th><th>Tracker rows</th><th>Pomodoros</th><th>First seen</th></tr>
    ${devices.map(d => `<tr><td>${esc(d.name ?? '—')}</td><td><code title="${esc(d.device)}">${esc(d.device.slice(0, 8))}</code></td><td>${stamp(d.lastPush)}</td>
      <td>${d.lastActivity ? stamp(d.lastActivity * 1000) : '—'}</td><td>${d.trackerRecords}</td><td>${d.pomodoroSessions}</td><td>${stamp(d.firstPush)}</td></tr>`).join('')}</table></div>`
}

async function route() {
  const path = location.pathname.replace(/\/$/, '')
  let m
  try {
    me ??= await api('/api/me')
    if (path === '/app') await dayPage(me.today)
    else if ((m = /^\/app\/day\/(\d{4}-\d{2}-\d{2})$/.exec(path))) await dayPage(m[1])
    else if ((m = /^\/app\/day\/(\d{4}-\d{2}-\d{2})\/records$/.exec(path))) await recordsPage(m[1])
    else if (path === '/app/history') await historyPage()
    else if (path === '/app/devices') await devicesPage()
    else { crumbs([['Not found']]); view.innerHTML = '<p>No such page. <a href="/app">Today</a></p>' }
  } catch (error) {
    if (error.message !== 'signed out') view.innerHTML = `<p class="error">Could not load: ${esc(error.message)}</p><p><a class="button" href="${esc(location.pathname + location.search)}">Retry</a></p>`
  }
}

// In-app navigation keeps the shell; every link stays a real URL.
document.addEventListener('click', e => {
  const a = e.target.closest('a')
  if (!a || a.target || a.origin !== location.origin || !a.pathname.startsWith('/app') || e.metaKey || e.ctrlKey || e.shiftKey) return
  e.preventDefault()
  history.pushState(null, '', a.href)
  window.scrollTo(0, 0)
  route()
})
window.addEventListener('popstate', route)

// ⋯ page menu: an installed PWA has no address bar, share sheet or reload.
const menu = document.getElementById('menu'), menuButton = document.getElementById('menu-button')
const toast = text => { const t = document.getElementById('toast'); t.textContent = text; t.hidden = false; setTimeout(() => { t.hidden = true }, 1500) }
if (navigator.share) menu.querySelector('[data-action=share]').hidden = false
menuButton.addEventListener('click', e => { e.stopPropagation(); menu.hidden = !menu.hidden; menuButton.setAttribute('aria-expanded', String(!menu.hidden)) })
document.addEventListener('click', () => { menu.hidden = true; menuButton.setAttribute('aria-expanded', 'false') })
menu.addEventListener('click', async e => {
  const action = e.target.closest('button')?.dataset.action
  if (action === 'top') window.scrollTo({ top: 0, behavior: 'smooth' })
  if (action === 'share') navigator.share({ title: document.title, url: location.href }).catch(() => {})
  if (action === 'copy') { await navigator.clipboard.writeText(location.href); toast('Link copied') }
  if (action === 'reload') location.reload()
  if (action === 'logout') {
    await fetch('/logout', { method: 'POST', credentials: 'same-origin' })
    location.href = '/'
  }
})

if ('serviceWorker' in navigator) navigator.serviceWorker.register('/sw.js').catch(() => {})
route()
