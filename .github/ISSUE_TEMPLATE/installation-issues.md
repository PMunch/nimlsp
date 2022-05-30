---
name: Installation issues
about: If you're facing installation issues
title: ''
labels: ''
assignees: ''

---

If you are getting an issue like this:
`/tmp/nimble_5830/githubcom_PMunchnimlsp_#head/src/nimlsppkg/suggestlib.nim(3, 19) Error: cannot open file: nimsuggest/nimsuggest`
It means that NimLSP can't find nimsuggest sources. This is probably because you have installed Nim through your package manager and not through `choosenim`. If this is the case then please read the README on how to fix it or search for any of the myriad of issues created around this. If you have actually read the README and done what it tells you to do in this case and it still complains, then please delete all this text and create an issue.
