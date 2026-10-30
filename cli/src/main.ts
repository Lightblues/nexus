#!/usr/bin/env node
import { run } from './cli.ts'

/** Piped input as is; at a terminal, one line without echo, so a pasted key never shows. */
async function readStdin(): Promise<string> {
  if (process.stdin.isTTY) {
    process.stderr.write('Key (hidden): ')
    process.stdin.setRawMode(true)
    return new Promise(resolve => {
      let line = ''
      const onData = (chunk: Buffer) => {
        for (const ch of chunk.toString('utf8')) {
          if (ch === '\r' || ch === '\n' || ch === '\u0004') {
            process.stdin.setRawMode(false)
            process.stdin.off('data', onData)
            process.stdin.pause()
            process.stderr.write('\n')
            return resolve(line)
          }
          if (ch === '\u0003') { process.stdin.setRawMode(false); process.exit(130) }
          line = ch === '\u007f' ? line.slice(0, -1) : line + ch
        }
      }
      process.stdin.on('data', onData)
    })
  }
  const chunks: Buffer[] = []
  for await (const chunk of process.stdin) chunks.push(Buffer.from(chunk))
  return Buffer.concat(chunks).toString('utf8')
}

run(process.argv.slice(2), {
  env: process.env,
  fetch,
  out: text => process.stdout.write(`${text}\n`),
  err: text => process.stderr.write(`${text}\n`),
  readStdin,
}).then(code => { process.exitCode = code }, error => {
  process.stderr.write(`nexus: ${(error as Error).stack ?? error}\n`)
  process.exitCode = 1
})
