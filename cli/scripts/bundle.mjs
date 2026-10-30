import { chmod, mkdir } from 'node:fs/promises'
import esbuild from 'esbuild'

await mkdir('dist', { recursive: true })
await esbuild.build({
  entryPoints: ['src/main.ts'],
  bundle: true,
  platform: 'node',
  format: 'esm',
  target: 'node20',
  outfile: 'dist/nexus.js',
  packages: 'external',
  legalComments: 'none',
})
await chmod('dist/nexus.js', 0o755)
