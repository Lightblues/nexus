import { addKey, addUser, listUsers, migrate, pgDb, type Access } from './store.ts'

const usage = `usage: npm run admin -- <command>
  users                              list users with their key and record counts
  add-user <name>                    create a user and print its first write key
  add-key <user-id> [write|read] [label]   print a new key for a user`

const url = process.env.NEXUS_DATABASE_URL?.trim()
if (!url) {
  console.error('NEXUS_DATABASE_URL is required')
  process.exit(1)
}
const [command, ...args] = process.argv.slice(2)
const db = pgDb(url)
try {
  await migrate(db)
  if (command === 'users') {
    for (const u of await listUsers(db)) console.log(`${u.id}\t${u.name}\tkeys=${u.keys}\trecords=${u.records}\t${new Date(u.createdAt).toISOString()}`)
  } else if (command === 'add-user' && args[0]) {
    const user = await addUser(db, args[0])
    console.log(`user ${user.id} (${user.name})\nwrite key (shown once): ${await addKey(db, user.id, 'write', 'first key')}`)
  } else if (command === 'add-key' && args[0] && [undefined, 'write', 'read'].includes(args[1])) {
    const access = (args[1] ?? 'write') as Access
    console.log(`${access} key for ${args[0]} (shown once): ${await addKey(db, args[0], access, args[2] ?? '')}`)
  } else {
    console.error(usage)
    process.exitCode = 1
  }
} finally {
  await db.close()
}
