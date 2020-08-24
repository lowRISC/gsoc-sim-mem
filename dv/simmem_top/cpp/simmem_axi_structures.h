// Copyright lowRISC contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

#ifndef SIMMEM_DV_AXI_STRUCTURES
#define SIMMEM_DV_AXI_STRUCTURES

#include "simmem_axi_dimensions.h"

///////////////////////////
// Write address request //
///////////////////////////

struct WriteAddress {
  // Shift offsets and widths in the packed representation
  static const uint64_t id_off, id_w;
  static const uint64_t addr_off, addr_w;
  static const uint64_t burst_len_off, burst_len_w;
  static const uint64_t burst_size_off, burst_size_w;
  static const uint64_t burst_type_off, burst_type_w;
  static const uint64_t lock_type_off, lock_type_w;
  static const uint64_t mem_type_off, mem_type_w;
  static const uint64_t prot_off, prot_w;
  static const uint64_t qos_off, qos_w;
  static const uint64_t region_off, region_w;

  uint64_t id;
  uint64_t addr;
  uint64_t burst_len;
  uint64_t burst_size;
  uint64_t burst_type;
  uint64_t lock_type;
  uint64_t mem_type;
  uint64_t prot;
  uint64_t qos;
  uint64_t region;

  uint64_t to_packed();
  void from_packed(uint64_t packed_val);
};

////////////////
// Write data //
////////////////

struct WriteData {
  // Shift offsets and widths in the packed representation
  static const uint64_t data_off, data_w;
  static const uint64_t strb_off, strb_w;
  static const uint64_t last_off, last_w;

  uint64_t data;
  uint64_t strb;
  uint64_t last;

  uint64_t to_packed();
  void from_packed(uint64_t packed_val);
};

//////////////////////////
// Read address request //
//////////////////////////

struct ReadAddress {
  // Shift offsets and widths in the packed representation
  static const uint64_t id_off, id_w;
  static const uint64_t addr_off, addr_w;
  static const uint64_t burst_len_off, burst_len_w;
  static const uint64_t burst_size_off, burst_size_w;
  static const uint64_t burst_type_off, burst_type_w;
  static const uint64_t lock_type_off, lock_type_w;
  static const uint64_t mem_type_off, mem_type_w;
  static const uint64_t prot_off, prot_w;
  static const uint64_t qos_off, qos_w;
  static const uint64_t region_off, region_w;

  uint64_t id;
  uint64_t addr;
  uint64_t burst_len;
  uint64_t burst_size;
  uint64_t burst_type;
  uint64_t lock_type;
  uint64_t mem_type;
  uint64_t prot;
  uint64_t qos;
  uint64_t region;

  uint64_t to_packed();
  void from_packed(uint64_t packed_val);
};

////////////////
// Read data //
////////////////

struct ReadData {
  // Shift offsets and widths in the packed representation
  static const uint64_t id_off, id_w;
  static const uint64_t data_off, data_w;
  static const uint64_t rsp_off, rsp_w;
  static const uint64_t last_off, last_w;

  uint64_t id;
  uint64_t data;
  uint64_t rsp;
  uint64_t last;

  uint64_t to_packed();
  void from_packed(uint64_t packed_val);
};

////////////////////
// Write response //
////////////////////

struct WriteResponse {
  // Shift offsets and widths in the packed representation
  static const uint64_t id_off, id_w;
  static const uint64_t rsp_off, rsp_w;

  uint64_t id;
  uint64_t rsp;

  uint64_t to_packed();
  void from_packed(uint64_t packed_val);
};

#endif  // SIMMEM_DV_AXI_STRUCTURES
