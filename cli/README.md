# @lightblues/nexus

Command line reader for a [Nexus](https://github.com/Lightblues/nexus) sync server: your days, activity rows, devices,
category rules, and synced settings. It talks to the server only, never to a Mac.

```bash
npm install -g @lightblues/nexus
nexus login --server https://nexus.example.com   # paste a key (read or write)
nexus today
nexus days --last 7
nexus doctor
```

`nexus help` lists every command. `--json` prints the server's JSON. `NEXUS_URL` and `NEXUS_KEY` override the saved
config (`~/.config/nexus/config.json`).

The `skills/nexus` directory is an agent skill describing the same commands.
