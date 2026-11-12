// Command __REPO_NAME__ prints a greeting.
package main

import (
	"fmt"

	"github.com/__OWNER__/__REPO_NAME__/internal/greet"
)

func main() {
	fmt.Println(greet.Hello("world"))
}
