# Security

Ambient runs locally with no network access. Its attack surface is the Unix socket at
`~/.ambient/ambient.sock` (mode 0600 inside a 0700 directory) and the agent config files it edits.

Please report vulnerabilities privately through GitHub's *Report a vulnerability* on this repository
rather than in a public issue. You'll get a reply within a week.
