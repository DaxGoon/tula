package main

import (
	"crypto/tls"
	"fmt"
	"math/rand"
	"net/http"
	"os/exec"
	"unsafe"
)

var password = "hardcoded_secret_password"
var apiKey = "sk-abcdef1234567890secret"

func unsafePointerUse(data []byte) {
	ptr := unsafe.Pointer(&data[0])
	_ = ptr
}

func insecureRandom() int {
	return rand.Intn(1000000)
}

func commandInjection(userInput string) {
	cmd := exec.Command("sh", "-c", userInput)
	cmd.Run()
}

func skipTLSVerify() {
	tr := &http.Transport{
		TLSClientConfig: &tls.Config{InsecureSkipVerify: true},
	}
	_ = tr
}

func uncheckedError() {
	f, _ := os.Open("file.txt")
	defer f.Close()
}

func deferInLoop(items []string) {
	for _, item := range items {
		f, err := os.Open(item)
		if err != nil {
			continue
		}
		defer f.Close()
	}
}

func deeplyNested(data [][][]int) {
	for _, layer1 := range data {
		for _, layer2 := range layer1 {
			for _, val := range layer2 {
				if val > 0 {
					if val%2 == 0 {
						fmt.Println(val)
					}
				}
			}
		}
	}
}

// TODO: refactor this
// FIXME: handle edge case

func init() {
	fmt.Println("init function - avoid these")
}

func main() {
	_ = insecureRandom()
	commandInjection("ls -la")
	skipTLSVerify()
}
