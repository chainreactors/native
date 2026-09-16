//go:build re2_cgo && re2_static && darwin && (amd64 || arm64)

package cre2

/*
#include "cre2.h"
#cgo darwin,amd64 LDFLAGS: -L${SRCDIR}/lib/darwin_amd64 -lre2_cre2 -lc++
#cgo darwin,arm64 LDFLAGS: -L${SRCDIR}/lib/darwin_arm64 -lre2_cre2 -lc++
*/
import "C"
