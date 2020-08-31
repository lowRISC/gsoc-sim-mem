// Copyright lowRISC contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

// The constants in this header must correspond to the ones defined in
// rtl/simmem_pkg.sv

#ifndef SIMMEM_DV_AXI_DIMENSIONS
#define SIMMEM_DV_AXI_DIMENSIONS

#include <stdint.h>

// The width of the main memory capacity.
const uint64_t GlobalMemCapaW = 19;  // Width

/////////////////
// AXI signals //
/////////////////

const uint64_t IDWidth = 2;
const uint64_t NumIds = 1 << IDWidth;

// Address field widths
const uint64_t AxAddrWidth = GlobalMemCapaW;
const uint64_t AxLenWidth = 8;
const uint64_t AxSizeWidth = 3;
const uint64_t AxBurstWidth = 2;
const uint64_t AxLockWidth = 1;
const uint64_t AxCacheWidth = 4;
const uint64_t AxProtWidth = 3;
const uint64_t AxQoSWidth = 4;
const uint64_t AxRegionWidth = 4;
const uint64_t AwUserWidth = 0;
const uint64_t ArUserWidth = 0;

// Data & response field widths
const uint64_t XLastWidth = 1;
// XReespWidth may be increased to 10 when testing, to have wider patterns to
// compare. This modification has to be performed in rtl/simmem_pkg
// simultaneously.
const uint64_t XRespWidth = 2;
const uint64_t WUserWidth = 0;
const uint64_t RUserWidth = 0;
const uint64_t BUserWidth = 0;

// Maximal value of any burst_size field, must be positive.
const uint64_t MaxBurstSizeField = 2;

// Effective max burst size (in number of elements)
const uint64_t MaxBurstEffSizeBytes = 1 << MaxBurstSizeField;
const uint64_t MaxBurstEffSizeBits = MaxBurstEffSizeBytes * 8;
const uint64_t WStrbWidth = MaxBurstEffSizeBytes;

// Maximal width of a single AXI message.
const uint64_t PackedW = 64;

typedef enum {
  BURST_FIXED = 0,
  BURST_INCR = 1,
  BURST_WRAP = 2,
  BURST_RESERVED = 3
} burst_type_e;

#endif  // SIMMEM_DV_AXI_DIMENSIONS
