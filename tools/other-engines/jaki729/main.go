// Drives the third-party engine package (copied unmodified into ./engine) with the
// matcher benchmark corpora: new -> ProcessOrder, cancel -> CancelOrder,
// replace -> CancelOrder + ProcessOrder (this engine has no replace). TIF is
// ignored (it has none), so this measures speed on the same op mix, not
// conformance.
package main

import (
	"bufio"
	"encoding/json"
	"fmt"
	"os"
	"strconv"
	"time"

	"jakibench/engine"
)

type cmd struct {
	Cmd     string  `json:"cmd"`
	OrderID uint64  `json:"order_id"`
	Side    string  `json:"side"`
	OType   string  `json:"otype"`
	Price   float64 `json:"price"`
	Qty     float64 `json:"qty"`
}

func load(path string, limit int) []cmd {
	f, err := os.Open(path)
	if err != nil {
		panic(err)
	}
	defer f.Close()
	sc := bufio.NewScanner(f)
	sc.Buffer(make([]byte, 1<<20), 1<<20)
	var out []cmd
	first := true
	for sc.Scan() {
		if first {
			first = false
			continue
		}
		var c cmd
		if err := json.Unmarshal(sc.Bytes(), &c); err != nil {
			continue
		}
		out = append(out, c)
		if limit > 0 && len(out) >= limit {
			break
		}
	}
	return out
}

func apply(me *engine.MatchingEngine, c cmd, ids map[uint64]string) {
	id := strconv.FormatUint(c.OrderID, 10)
	switch c.Cmd {
	case "new":
		o := mk(id, c)
		me.ProcessOrder(o)
	case "cancel":
		me.CancelOrder("X", id)
	case "replace":
		// look up side from the last known new; keep it simple: store side per id
		side := ids[c.OrderID]
		me.CancelOrder("X", id)
		o := &engine.Order{ID: id, Symbol: "X", Type: engine.LIMIT, Quantity: c.Qty, Price: c.Price}
		if side == "bid" {
			o.Side = engine.BUY
		} else {
			o.Side = engine.SELL
		}
		me.ProcessOrder(o)
	}
}

func mk(id string, c cmd) *engine.Order {
	o := &engine.Order{ID: id, Symbol: "X", Quantity: c.Qty, Price: c.Price, Type: engine.LIMIT}
	if c.Side == "bid" {
		o.Side = engine.BUY
	} else {
		o.Side = engine.SELL
	}
	if c.OType == "market" {
		o.Type = engine.MARKET
	}
	return o
}

func main() {
	prefix := os.Args[1]
	limit := 0
	if len(os.Args) > 2 {
		limit, _ = strconv.Atoi(os.Args[2])
	}
	setup := load(prefix+".setup.cmd.jsonl", 0)
	run := load(prefix+".run.cmd.jsonl", limit)
	ids := map[uint64]string{}
	for _, c := range setup {
		ids[c.OrderID] = c.Side
	}
	for _, c := range run {
		if c.Cmd == "new" {
			ids[c.OrderID] = c.Side
		}
	}
	me := engine.NewMatchingEngine()
	for _, c := range setup {
		apply(me, c, ids)
	}
	t0 := time.Now()
	for _, c := range run {
		apply(me, c, ids)
	}
	d := time.Since(t0)
	fmt.Printf("%s: %d ops in %.3fs = %.0f ops/s (%.1f us/op)\n", prefix[len(prefix)-8:], len(run), d.Seconds(), float64(len(run))/d.Seconds(), d.Seconds()*1e6/float64(len(run)))
}
