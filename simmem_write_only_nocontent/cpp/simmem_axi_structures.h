// Copyright lowRISC contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

#ifndef SIMMEM_DV_AXI_STRUCTURES
#define SIMMEM_DV_AXI_STRUCTURES

#include "simmem_axi_dimensions.h"

///////////////////////////
// Write address request //
///////////////////////////

class WriteAddressRequest {
 public:
  // Shift offsets in the packed representations
  static const uint64_t id_offset, id_width;
  static const uint64_t addr_offset, addr_width;
  static const uint64_t burst_length_offset, burst_length_width;
  static const uint64_t burst_size_offset, burst_size_width;
  static const uint64_t burst_type_offset, burst_type_width;
  static const uint64_t lock_type_offset, lock_type_width;
  static const uint64_t memory_type_offset, memory_type_width;
  static const uint64_t protection_type_offset, protection_type_width;
  static const uint64_t qos_offset, qos_width;

  WriteAddressRequest(uint64_t id, uint64_t addr, uint64_t burst_length,
                      uint64_t burst_size, uint64_t burst_type,
                      uint64_t lock_type, uint64_t memory_type,
                      uint64_t protection_type, uint64_t qos);

  WriteAddressRequest(uint64_t packed);

  ~WriteAddressRequest();

  // Getters
  uint64_t get_id();
  uint64_t get_addr();
  uint64_t get_burst_length();
  uint64_t get_burst_size();
  uint64_t get_burst_type();
  uint64_t get_lock_type();
  uint64_t get_memory_type();
  uint64_t get_protection_type();
  uint64_t get_qos();
  uint64_t get_packed();

  // Setters
  void set_id(uint64_t id);
  void set_addr(uint64_t addr);
  void set_burst_length(uint64_t burst_length);
  void set_burst_size(uint64_t burst_size);
  void set_burst_type(uint64_t burst_type);
  void set_lock_type(uint64_t lock_type);
  void set_memory_type(uint64_t memory_type);
  void set_protection_type(uint64_t protection_type);
  void set_qos(uint64_t qos);
  void set_packed(uint64_t packed);

 private:
  /**
   * Generates the packed field, once all the subfields are given.
   */
  void gen_packed(uint64_t id, uint64_t addr, uint64_t burst_length,
                  uint64_t burst_size, uint64_t burst_type, uint64_t lock_type,
                  uint64_t memory_type, uint64_t protection_type, uint64_t qos);

  // Packed representation of the message
  uint64_t packed;
};

////////////////////
// Write response //
////////////////////

class WriteResponse {
 public:
  // Shift offsets in the packed representations
  static const uint64_t id_offset, id_width;
  static const uint64_t content_offset, content_width;

  WriteResponse(uint64_t id, uint64_t content);

  WriteResponse(uint64_t packed);

  ~WriteResponse();

  // Getters
  uint64_t get_id();
  uint64_t get_content();
  uint64_t get_packed();

  // Setters
  void set_id(uint64_t id);
  void set_content(uint64_t content);
  void set_packed(uint64_t packed);

 private:
  /**
   * Generates the packed field, once all the subfields are given.
   */
  void gen_packed(uint64_t id, uint64_t content);

  // Packed representation of the message
  uint64_t packed;
};

#endif  // SIMMEM_DV_AXI_STRUCTURES
