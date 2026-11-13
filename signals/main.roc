app [main] {
	pf: platform "https://github.com/lukewilliamboswell/roc-signals/releases/download/0.5.0/2SYUPo9uKFPJDvTyXiwsLEqHvmq7UMgaY4hdgMiSsSEF.tar.zst",
	fsrs: "../packages/fsrs/main.roc",
	json: "../packages/json/main.roc",
	study: "../packages/study/main.roc",
}

import pf.Engine
import View

## Lyceum Study on roc-signals 0.5.0, ported from the Elm app (src/):
## `roc build --target=wasm32` gives the browser module and
## `roc build --target=x64musl` its native spec runner (see Kaifile.roc).
main : Engine.Program
main = View.program
