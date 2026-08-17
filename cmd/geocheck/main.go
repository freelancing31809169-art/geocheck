// Command geocheck reports where the internet thinks you are and how
// directly your traffic reaches the networks that carry it.
package main

import (
	"os"

	"github.com/remnawave/geocheck/internal/cli"
)

func main() {
	os.Exit(cli.Run(os.Args[1:]))
}
