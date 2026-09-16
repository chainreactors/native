//go:build re2_cgo && re2_static && linux && amd64

package cre2

/*
#include "cre2.h"
#cgo LDFLAGS: -lre2_cre2 -static-libgcc -Wl,-Bstatic -lstdc++ -Wl,-Bdynamic
*/
import "C"
