//go:build re2_cgo && re2_static && linux && arm64

package cre2

/*
#include "cre2.h"
#cgo LDFLAGS: -L${SRCDIR}/lib/linux_arm64 -lre2_cre2 -static-libgcc -Wl,-Bstatic -lstdc++ -Wl,-Bdynamic
*/
import "C"
