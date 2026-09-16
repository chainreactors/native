//go:build re2_cgo && re2_static && windows && amd64

package cre2

/*
#include "cre2.h"
#cgo LDFLAGS: -L${SRCDIR}/lib/windows_amd64 -Wl,-Bstatic -Wl,--start-group -lre2_cre2 -lstdc++ -lwinpthread -lgcc -lgcc_eh -Wl,--end-group -Wl,-Bdynamic
*/
import "C"
