# Driver for jaki729/High-Frequency-Trading-Matching-Engine

Feeds the matcher benchmark corpora (`bench/<w>.setup.cmd.jsonl` / `.run.cmd.jsonl`)
into the third-party Go engine's `engine` package: new -> `ProcessOrder`,
cancel -> `CancelOrder`, replace -> `CancelOrder` + `ProcessOrder` (it has no replace).
It has no time-in-force, so IOC/FOK/post-only are treated as plain limits: this
measures speed on the same operation mix, **not** conformance.

```sh
git clone https://github.com/jaki729/High-Frequency-Trading-Matching-Engine /tmp/jaki
mkdir -p engine && cp /tmp/jaki/engine/*.go engine/     # unmodified copy
go build -o jb . && ./jb ../../../bench/w5_1k 200000
```
