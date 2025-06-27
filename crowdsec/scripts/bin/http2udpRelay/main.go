package main

import (
	"fmt"
	"io"
	"net"
	"net/http"
	"os"
	"time"
)

func handler(w http.ResponseWriter, r *http.Request) {
	body, _ := io.ReadAll(r.Body)
	now := time.Now().Format("Jan 02 15:04:05")
	hostname, _ := os.Hostname()
	msg := fmt.Sprintf("<14>%s %s http-to-syslog: %s", now, hostname, string(body))

	// Log the message that will be sent to syslog
	fmt.Println("Sending to syslog:", msg)

	conn, err := net.Dial("udp", "127.0.0.1:4242")
	if err != nil {
		fmt.Println("Failed to open UDP connection:", err)
		w.WriteHeader(500)
		return
	}

	_, err = conn.Write([]byte(msg))
	if err != nil {
		fmt.Println("Failed to send message over UDP:", err)
		w.WriteHeader(500)
	} else {
		fmt.Println("Message successfully sent.")
		w.WriteHeader(204)
	}

	conn.Close()
}

// build with GOOS=linux GOARCH=amd64 go build -ldflags="-s -w" -o http-to-syslog main.go
func main() {
	http.HandleFunc("/", handler)
	fmt.Println("Listening on :8888")
	http.ListenAndServe(":8888", nil)
}
