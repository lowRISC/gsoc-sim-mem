// Copyright lowRISC contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

#include "simmem_axi_structures.h"

///////////////////////////
// Write address request //
///////////////////////////

// Static constant definition (widths)
const uint64_t WriteAddressRequest::id_width = IDWidth;
const uint64_t WriteAddressRequest::addr_width = AxAddrWidth;
const uint64_t WriteAddressRequest::burst_length_width = AxLenWidth;
const uint64_t WriteAddressRequest::burst_size_width = AxSizeWidth;
const uint64_t WriteAddressRequest::burst_type_width = AxBurstWidth;
const uint64_t WriteAddressRequest::lock_type_width = AxLockWidth;
const uint64_t WriteAddressRequest::memory_type_width = AxCacheWidth;
const uint64_t WriteAddressRequest::protection_type_width = AxProtWidth;
const uint64_t WriteAddressRequest::qos_width = AxQoSWidth;

// Static constant definition (offsets)
const uint64_t WriteAddressRequest::id_offset = 0;
const uint64_t WriteAddressRequest::addr_offset =
    WriteAddressRequest::id_offset + WriteAddressRequest::id_width;
const uint64_t WriteAddressRequest::burst_length_offset =
    WriteAddressRequest::addr_offset + WriteAddressRequest::addr_width;
const uint64_t WriteAddressRequest::burst_size_offset =
    WriteAddressRequest::burst_length_offset +
    WriteAddressRequest::burst_length_width;
const uint64_t WriteAddressRequest::burst_type_offset =
    WriteAddressRequest::burst_size_offset +
    WriteAddressRequest::burst_size_width;
const uint64_t WriteAddressRequest::lock_type_offset =
    WriteAddressRequest::burst_type_offset +
    WriteAddressRequest::burst_type_width;
const uint64_t WriteAddressRequest::memory_type_offset =
    WriteAddressRequest::lock_type_offset +
    WriteAddressRequest::lock_type_width;
const uint64_t WriteAddressRequest::protection_type_offset =
    WriteAddressRequest::memory_type_offset +
    WriteAddressRequest::memory_type_width;
const uint64_t WriteAddressRequest::qos_offset =
    WriteAddressRequest::protection_type_offset +
    WriteAddressRequest::protection_type_width;

// Method implementations
WriteAddressRequest::WriteAddressRequest(
    uint64_t id, uint64_t addr, uint64_t burst_length, uint64_t burst_size,
    uint64_t burst_type, uint64_t lock_type, uint64_t memory_type,
    uint64_t protection_type, uint64_t qos) {
  gen_packed(id, addr, burst_length, burst_size, burst_type, lock_type,
             memory_type, protection_type, qos);
}

WriteAddressRequest::WriteAddressRequest(uint64_t packed) {
  this->packed = packed;
}

void WriteAddressRequest::gen_packed(uint64_t id, uint64_t addr,
                                     uint64_t burst_length, uint64_t burst_size,
                                     uint64_t burst_type, uint64_t lock_type,
                                     uint64_t memory_type,
                                     uint64_t protection_type, uint64_t qos) {
  packed = 0;
  set_id(id);
  set_addr(addr);
  set_burst_length(burst_length);
  set_burst_size(burst_size);
  set_burst_type(burst_type);
  set_lock_type(lock_type);
  set_memory_type(memory_type);
  set_protection_type(protection_type);
  set_qos(qos);
}

// Setters
void WriteAddressRequest::set_id(uint64_t id) {
  if (!id_width) {
    return;
  }
  uint64_t low_mask = (1UL << (PackedWidth - 1)) >> (PackedWidth - id_width);
  packed &= low_mask << id_offset;
  packed |= (~low_mask & id) << id_offset;
}

void WriteAddressRequest::set_addr(uint64_t addr) {
  if (!addr_width) {
    return;
  }
  uint64_t low_mask = (1UL << (PackedWidth - 1)) >> (PackedWidth - addr_width);
  packed &= low_mask << addr_offset;
  packed |= (~low_mask & addr) << addr_offset;
}

void WriteAddressRequest::set_burst_length(uint64_t burst_length) {
  if (!burst_length_width) {
    return;
  }
  uint64_t low_mask =
      (1UL << (PackedWidth - 1)) >> (PackedWidth - burst_length_width);
  packed &= low_mask << burst_length_offset;
  packed |= (~low_mask & burst_length) << burst_length_offset;
}

void WriteAddressRequest::set_burst_size(uint64_t burst_size) {
  if (!burst_size_width) {
    return;
  }
  uint64_t low_mask =
      (1UL << (PackedWidth - 1)) >> (PackedWidth - burst_size_width);
  packed &= low_mask << burst_size_offset;
  packed |= (~low_mask & burst_size) << burst_size_offset;
}

void WriteAddressRequest::set_burst_type(uint64_t burst_type) {
  if (!burst_type_width) {
    return;
  }
  uint64_t low_mask =
      (1UL << (PackedWidth - 1)) >> (PackedWidth - burst_type_width);
  packed &= low_mask << burst_type_offset;
  packed |= (~low_mask & burst_type) << burst_type_offset;
}

void WriteAddressRequest::set_lock_type(uint64_t lock_type) {
  if (!lock_type_width) {
    return;
  }
  uint64_t low_mask =
      (1UL << (PackedWidth - 1)) >> (PackedWidth - lock_type_width);
  packed &= low_mask << lock_type_offset;
  packed |= (~low_mask & lock_type) << lock_type_offset;
}

void WriteAddressRequest::set_memory_type(uint64_t memory_type) {
  if (!memory_type_width) {
    return;
  }
  uint64_t low_mask =
      (1UL << (PackedWidth - 1)) >> (PackedWidth - memory_type_width);
  packed &= low_mask << memory_type_offset;
  packed |= (~low_mask & memory_type) << memory_type_offset;
}

void WriteAddressRequest::set_protection_type(uint64_t protection_type) {
  if (!protection_type_width) {
    return;
  }
  uint64_t low_mask =
      (1UL << (PackedWidth - 1)) >> (PackedWidth - protection_type_width);
  packed &= low_mask << protection_type_offset;
  packed |= (~low_mask & protection_type) << protection_type_offset;
}

void WriteAddressRequest::set_qos(uint64_t qos) {
  if (!qos_width) {
    return;
  }
  uint64_t low_mask = (1UL << (PackedWidth - 1)) >> (PackedWidth - qos_width);
  packed &= low_mask << qos_offset;
  packed |= (~low_mask & qos) << qos_offset;
}

void WriteAddressRequest::set_packed(uint64_t packed) { this->packed = packed; }

// Getters
uint64_t WriteAddressRequest::get_id(void) {
  if (!id_width) {
    return 0;
  }
  uint64_t low_mask = (1UL << (PackedWidth - 1)) >> (PackedWidth - id_width);
  return (packed & (low_mask << id_offset)) >> id_offset;
}

uint64_t WriteAddressRequest::get_addr(void) {
  if (!addr_width) {
    return 0;
  }
  uint64_t low_mask = (1UL << (PackedWidth - 1)) >> (PackedWidth - addr_width);
  return (packed & (low_mask << addr_offset)) >> addr_offset;
}

uint64_t WriteAddressRequest::get_burst_length(void) {
  if (!burst_length_width) {
    return 0;
  }
  uint64_t low_mask =
      (1UL << (PackedWidth - 1)) >> (PackedWidth - burst_length_width);
  return (packed & (low_mask << burst_length_offset)) >> burst_length_offset;
}

uint64_t WriteAddressRequest::get_burst_size(void) {
  if (!burst_size_width) {
    return 0;
  }
  uint64_t low_mask =
      (1UL << (PackedWidth - 1)) >> (PackedWidth - burst_size_width);
  return (packed & (low_mask << burst_size_offset)) >> burst_size_offset;
}

uint64_t WriteAddressRequest::get_burst_type(void) {
  if (!burst_type_width) {
    return 0;
  }
  uint64_t low_mask =
      (1UL << (PackedWidth - 1)) >> (PackedWidth - burst_type_width);
  return (packed & (low_mask << burst_type_offset)) >> burst_type_offset;
}

uint64_t WriteAddressRequest::get_lock_type(void) {
  if (!lock_type_width) {
    return 0;
  }
  uint64_t low_mask =
      (1UL << (PackedWidth - 1)) >> (PackedWidth - lock_type_width);
  return (packed & (low_mask << lock_type_offset)) >> lock_type_offset;
}

uint64_t WriteAddressRequest::get_memory_type(void) {
  if (!memory_type_width) {
    return 0;
  }
  uint64_t low_mask =
      (1UL << (PackedWidth - 1)) >> (PackedWidth - memory_type_width);
  return (packed & (low_mask << memory_type_offset)) >> memory_type_offset;
}

uint64_t WriteAddressRequest::get_protection_type(void) {
  if (!protection_type_width) {
    return 0;
  }
  uint64_t low_mask =
      (1UL << (PackedWidth - 1)) >> (PackedWidth - protection_type_width);
  return (packed & (low_mask << protection_type_offset)) >>
         protection_type_offset;
}

uint64_t WriteAddressRequest::get_qos(void) {
  if (!qos_width) {
    return 0;
  }
  uint64_t low_mask = (1UL << (PackedWidth - 1)) >> (PackedWidth - qos_width);
  return (packed & (low_mask << qos_offset)) >> qos_offset;
}

uint64_t WriteAddressRequest::get_packed(void) { return packed; }

////////////////////
// Write response //
////////////////////

// Static constant definition (widths)
const uint64_t WriteResponse::id_width = IDWidth;
const uint64_t WriteResponse::content_width = XRespWidth;

// Static constant definition (offsets)
const uint64_t WriteResponse::id_offset = 0;
const uint64_t WriteResponse::content_offset =
    WriteResponse::id_offset + WriteResponse::id_width;

// Method implementations
WriteResponse::WriteResponse(uint64_t id, uint64_t content) {
  gen_packed(id, content);
}

WriteResponse::WriteResponse(uint64_t packed) { this->packed = packed; }

void WriteResponse::gen_packed(uint64_t id, uint64_t content) {
  packed = 0;
  set_id(id);
  set_content(content);
}

// Setters
void WriteResponse::set_id(uint64_t id) {
  uint64_t low_mask = (1UL << (PackedWidth - 1)) >> (PackedWidth - id_width);
  packed &= low_mask << id_offset;
  packed |= (~low_mask & id) << id_offset;
}

void WriteResponse::set_content(uint64_t content) {
  uint64_t low_mask =
      (1UL << (PackedWidth - 1)) >> (PackedWidth - content_width);
  packed &= low_mask << content_offset;
  packed |= (~low_mask & content) << content_offset;
}

void WriteResponse::set_packed(uint64_t content) { this->packed = packed; }

// Getters
uint64_t WriteResponse::get_id(void) {
  uint64_t low_mask = (1UL << (PackedWidth - 1)) >> (PackedWidth - id_width);
  return (packed & (low_mask << id_offset)) >> id_offset;
}

uint64_t WriteResponse::get_content(void) {
  uint64_t low_mask =
      (1UL << (PackedWidth - 1)) >> (PackedWidth - content_width);
  return (packed & (low_mask << content_offset)) >> content_offset;
}

uint64_t WriteResponse::get_packed(void) { return packed; }
