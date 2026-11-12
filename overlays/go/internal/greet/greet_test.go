package greet

import "testing"

func TestHello(t *testing.T) {
	if got, want := Hello("world"), "Hello, world!"; got != want {
		t.Errorf("Hello(%q) = %q, want %q", "world", got, want)
	}
}
