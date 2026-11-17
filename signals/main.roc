app [main] {
	pf: platform "https://github.com/lukewilliamboswell/roc-signals/releases/download/0.6.0/3kWiwEo2KWAQTrPidpkPTMNGCY6AX7qup9K6tJVYMhB9.tar.zst",
	fsrs: "../packages/fsrs/main.roc",
	json: "../packages/json/main.roc",
	study: "../packages/study/main.roc",
}

import pf.Engine
import View

## Lyceum Study on roc-signals 0.6.0, ported from the Elm app (src/):
## `roc build --target=wasm32` gives the browser module and
## `roc build --target=x64musl` its native spec runner (see Kaifile.roc).
# The app keeps its state in a root state, not a store.
Store : {}

main : Engine.Program(Store)
main = View.program
