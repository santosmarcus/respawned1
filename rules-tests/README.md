# Rules tests

Emulator tests for `../firestore.rules` and `../storage.rules`.

```bash
npm install
npm test
```

`npm test` starts the Firestore and Storage emulators, runs `tests/`, and shuts them down. The Firebase CLI needs Java 21+. If `java -version` shows an older one, point `JAVA_HOME` at Android Studio's bundled runtime for the run:

```bash
JAVA_HOME="/c/Program Files/Android/Android Studio/jbr" PATH="/c/Program Files/Android/Android Studio/jbr/bin:$PATH" npm test
```

`tests/setup.js` seeds the personas every test uses (platform admin, staff of two approved organizations, a draft organization's owner, a reporter, an adopter, two transporters and an outsider). Add a test next to the rule you change: one for the flow the app needs, one for the abuse it must block.

Denied requests may log "maximum of 1000 expressions"; that's Firestore giving up on a request it would deny anyway. `tests/expression-budget.test.js` checks that the longest legitimate paths still fit.
