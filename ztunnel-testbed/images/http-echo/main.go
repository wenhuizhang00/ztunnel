package main

import (
	"flag"
	"fmt"
	"log"
	"net/http"
	"os"
)

func main() {
	text := flag.String("text", os.Getenv("ECHO_TEXT"), "text to echo")
	listen := flag.String("listen", ":8080", "address:port to listen on")
	statusCode := flag.Int("status-code", 200, "HTTP status code")
	flag.Parse()

	if *text == "" {
		*text = "hello"
	}

	http.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(*statusCode)
		fmt.Fprint(w, *text)
	})

	log.Printf("Listening on %s, text=%q", *listen, *text)
	log.Fatal(http.ListenAndServe(*listen, nil))
}
