// SPDX-License-Identifier: Apache-2.0

#ifndef FIVE_STAGE_RVMODEL_MACROS_H
#define FIVE_STAGE_RVMODEL_MACROS_H

// The DUT runner watches a fixed 64-bit tohost mailbox. The Sail signature
// build overrides this macro and supplies its own .tohost section.
#define RVMODEL_DATA_SECTION

// This core implements a deliberately finite M-mode CSR subset. Bypass ACT4's
// standard Sm boot, which would access unimplemented CSRs such as
// mcountinhibit and mhpmevent*. Do not define STANDARD_SM_SUPPORTED here.
#define RVMODEL_BOOT_TO_MMODE

#define RVMODEL_HALT_PASS  \
  li x1, 1                ;\
  li t0, 0x8003fff0       ;\
  sw x1, 0(t0)            ;\
  sw x0, 4(t0)            ;\
1:                        ;\
  j 1b                    ;\

#define RVMODEL_HALT_FAIL  \
  li x1, 3                ;\
  li t0, 0x8003fff0       ;\
  sw x1, 0(t0)            ;\
  sw x0, 4(t0)            ;\
1:                        ;\
  j 1b                    ;\

// The Python runner emits the ACT4 RVCP summary from the mailbox result.
#define RVMODEL_IO_INIT(_R1, _R2, _R3)
#define RVMODEL_IO_WRITE_STR(_R1, _R2, _R3, _STR_PTR)

#define RVMODEL_INTERRUPT_LATENCY 10
#define RVMODEL_TIMER_INT_SOON_DELAY 100

#define RVMODEL_SET_MEXT_INT(_R1, _R2)
#define RVMODEL_CLR_MEXT_INT(_R1, _R2)
#define RVMODEL_SET_MSW_INT(_R1, _R2)
#define RVMODEL_CLR_MSW_INT(_R1, _R2)
#define RVMODEL_SET_SEXT_INT(_R1, _R2)
#define RVMODEL_CLR_SEXT_INT(_R1, _R2)
#define RVMODEL_SET_SSW_INT(_R1, _R2)
#define RVMODEL_CLR_SSW_INT(_R1, _R2)

#endif
