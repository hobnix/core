// Example command extension in Go, standard library only: `hs ext hello greet [name]` and `hs ext hello count <n>`.
// There is no Go library on purpose (docs/extensions-sdk.md): the protocol is five message types, and this file is the whole of it.
//
// Try it without the core:
//
//	go build -o hello . && python3 ../../../scripts/lib/ext_proto.py call --command greet --arg Ada -- ./hello
package main

import (
	"bufio"
	"encoding/json"
	"fmt"
	"os"
	"strconv"
)

type request struct {
	V       int      `json:"v"`
	ID      string   `json:"id"`
	Command []string `json:"command"`
	Argv    []string `json:"argv"`
	Lang    string   `json:"lang"`
	Caller  string   `json:"caller"`
}

// send writes one message: one JSON object on one line of stdout.
func send(m map[string]any) {
	m["v"] = 1
	b, _ := json.Marshal(m)
	fmt.Fprintf(os.Stdout, "%s\n", b)
}

func fail(code, message string) {
	send(map[string]any{"type": "result", "ok": false, "error": map[string]any{"code": code, "message": message}})
	os.Exit(1)
}

func ok(data any, text string) {
	m := map[string]any{"type": "result", "ok": true}
	if data != nil {
		m["data"] = data
	}
	if text != "" {
		m["text"] = text
	}
	send(m)
	os.Exit(0)
}

func main() {
	line, _ := bufio.NewReaderSize(os.Stdin, 1<<20).ReadString('\n')
	var req request
	if err := json.Unmarshal([]byte(line), &req); err != nil || req.V != 1 {
		send(map[string]any{"type": "result", "ok": false, "error": map[string]any{
			"code": "unsupported_version", "message": "this extension speaks protocol version 1 only", "supported": []int{1}}})
		os.Exit(1)
	}
	if len(req.Command) == 0 {
		fail("not_found", "no such command")
	}
	switch req.Command[0] {
	case "greet":
		name := "world"
		if len(req.Argv) > 0 {
			name = req.Argv[0]
		}
		send(map[string]any{"type": "log", "level": "info", "text": "greeting"})
		send(map[string]any{"type": "event", "kind": "pkg.hello.greeted", "subject": name})
		ok(map[string]any{"greeting": "hello " + name}, "hello "+name)
	case "count":
		n := 0
		if len(req.Argv) > 0 {
			n, _ = strconv.Atoi(req.Argv[0])
		}
		if n < 1 || n > 10 {
			fail("bad_request", "count needs a number from 1 to 10")
		}
		for i := 1; i <= n; i++ {
			send(map[string]any{"type": "progress", "fraction": float64(i) / float64(n), "text": fmt.Sprintf("step %d of %d", i, n)})
		}
		ok(map[string]any{"counted": n}, "")
	default:
		fail("not_found", "no such command")
	}
}
