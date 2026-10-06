#ifndef TERMUX_PTHREAD_CANCEL_COMPAT_H
#define TERMUX_PTHREAD_CANCEL_COMPAT_H

/*
 * bionic (Android) deliberately does not implement thread cancellation:
 * neither <pthread.h> declares pthread_cancel() nor does libc export the
 * symbol. ngspice's xspice Verilog co-simulation shim calls it in
 * cr_cleanup() purely to wake a thread that is parked in
 * pthread_cond_wait() so that it can unwind and exit.
 *
 * A no-op is the correct substitute for our purposes: cr_cleanup() already
 * signals the condvar and joins the thread right afterwards. This is only
 * reached from the Verilog/Icarus co-simulation code path, which KiCad's
 * ngspice integration never uses.
 */
#include <pthread.h>

static inline int pthread_cancel(pthread_t thread) {
    (void) thread;
    return 0;
}

#endif /* TERMUX_PTHREAD_CANCEL_COMPAT_H */
