//go:build re2_cgo && re2_static && darwin && (amd64 || arm64)

package cre2

/*
#include "cre2.h"
#cgo LDFLAGS: -lre2_cre2 -lc++
*/
import "C"
