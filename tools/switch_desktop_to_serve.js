const fs = require('fs')
const path = require('path')

const appData = process.env.APPDATA
const dir = path.join(appData, 'ai.opencode.desktop')
const settingsPath = path.join(dir, 'opencode.settings')
const globalPath = path.join(dir, 'opencode.global.dat')
const backupDir = path.join(dir, 'backup-before-unify-' + Date.now())

const SERVER_URL = 'http://127.0.0.1:4096'
const PROJECT = 'D:\\Huawei\\OpenHarmony\\work\\OpenCodeHarmony'

fs.mkdirSync(backupDir, { recursive: true })
fs.copyFileSync(settingsPath, path.join(backupDir, 'opencode.settings'))
fs.copyFileSync(globalPath, path.join(backupDir, 'opencode.global.dat'))
console.log('backup ->', backupDir)

// 1) default server URL for Desktop startup
const settings = JSON.parse(fs.readFileSync(settingsPath, 'utf8'))
settings.defaultServerUrl = SERVER_URL
fs.writeFileSync(settingsPath, JSON.stringify(settings, null, '\t') + '\n', 'utf8')
console.log('settings.defaultServerUrl =', settings.defaultServerUrl)

// 2) global store: server list + home selection + projects under remote scope
const globalObj = JSON.parse(fs.readFileSync(globalPath, 'utf8'))

function parseNested(key) {
  const raw = globalObj[key]
  if (typeof raw !== 'string') return null
  return JSON.parse(raw)
}

function writeNested(key, value) {
  // keep compact JSON like original nested blobs
  globalObj[key] = JSON.stringify(value)
}

const server = parseNested('server') || { list: [], projects: {}, lastProject: {}, recentlyClosed: {} }
const remoteConn = {
  type: 'http',
  displayName: 'Phone Sync (4096)',
  http: {
    url: SERVER_URL,
    username: 'opencode',
    password: 'opencode'
  }
}

// upsert by url
const list = Array.isArray(server.list) ? server.list.slice() : []
const idx = list.findIndex((x) => x && x.type === 'http' && x.http && x.http.url === SERVER_URL)
if (idx >= 0) list[idx] = remoteConn
else list.push(remoteConn)
server.list = list

if (!server.projects) server.projects = {}
if (!server.lastProject) server.lastProject = {}
if (!server.recentlyClosed) server.recentlyClosed = {}

// copy local projects into remote scope so Desktop can open them
const localProjects = server.projects.local || []
const remoteProjects = server.projects[SERVER_URL] || []
const merged = []
const seen = new Set()
for (const p of [...remoteProjects, ...localProjects]) {
  if (!p || !p.worktree || seen.has(p.worktree)) continue
  seen.add(p.worktree)
  merged.push({ worktree: p.worktree, expanded: p.expanded !== false })
}
// ensure current project first
merged.sort((a, b) => (a.worktree === PROJECT ? -1 : b.worktree === PROJECT ? 1 : 0))
server.projects[SERVER_URL] = merged
server.lastProject[SERVER_URL] = server.lastProject.local || PROJECT

writeNested('server', server)
console.log('server.list =', JSON.stringify(server.list, null, 2))
console.log('remote projects count =', merged.length)

// layout.home.selection -> remote server
const layout = parseNested('layout')
if (layout) {
  if (!layout.home) layout.home = {}
  layout.home.selection = {
    server: SERVER_URL,
    directory: PROJECT
  }
  writeNested('layout', layout)
  console.log('layout.home.selection =', layout.home.selection)
} else {
  console.warn('layout missing, skip home.selection')
}

fs.writeFileSync(globalPath, JSON.stringify(globalObj, null, '\t') + '\n', 'utf8')
console.log('updated', globalPath)
console.log('DONE')
