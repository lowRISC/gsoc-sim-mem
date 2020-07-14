// Copyright lowRISC contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

#include "simmem_axi_structures.h"

#include <iostream>  // TODO: Remove

///////////////////////////
// Write address request //
///////////////////////////

// Static constant definition (widths)
const uint64_t WriteAddressRequest::id_w = IDWidth;
const uint64_t WriteAddressRequest::addr_w = AxAddrWidth;
const uint64_t WriteAddressRequest::burst_len_w = AxLenWidth;
const uint64_t WriteAddressRequest::burst_size_w = AxSizeWidth;
const uint64_t WriteAddressRequest::burst_type_w = AxBurstWidth;
const uint64_t WriteAddressRequest::lock_type_w = AxLockWidth;
const uint64_t WriteAddressRequest::memtype_w = AxCacheWidth;
const uint64_t WriteAddressRequest::prot_w = AxProtWidth;
const uint64_t WriteAddressRequest::qos_w = AxQoSWidth;

// Static constant definition (offsets)
const uint64_t WriteAddressRequest::id_off = 0UL;
const uint64_t WriteAddressRequest::addr_off =
    WriteAddressRequest::id_off + WriteAddressRequest::id_w;
const uint64_t WriteAddressRequest::burst_len_off =
    WriteAddressRequest::addr_off + WriteAddressRequest::addr_w;
const uint64_t WriteAddressRequest::burst_size_off =
    WriteAddressRequest::burst_len_off + WriteAddressRequest::burst_len_w;
const uint64_t WriteAddressRequest::burst_type_off =
    WriteAddressRequest::burst_size_off + WriteAddressRequest::burst_size_w;
const uint64_t WriteAddressRequest::lock_type_off =
    WriteAddressRequest::burst_type_off + WriteAddressRequest::burst_type_w;
const uint64_t WriteAddressRequest::memtype_off =
    WriteAddressRequest::lock_type_off + WriteAddressRequest::lock_type_w;
const uint64_t WriteAddressRequest::prot_off =
    WriteAddressRequest::memtype_off + WriteAddressRequest::memtype_w;
const uint64_t WriteAddressRequest::qos_off =
    WriteAddressRequest::prot_off + WriteAddressRequest::prot_w;

void WriteAddressRequest::from_packed(uint64_t packed) {
  uint64_t low_mask;

  if (id_w) {
    low_mask = ~(1L << (PackedW - 1)) >> (PackedW - 1 - id_w);
    id = low_mask & ((packed & (low_mask << id_off)) >> id_off);
  }

  if (addr_w) {
    low_mask = ~(1L << (PackedW - 1)) >> (PackedW - 1 - addr_w);
    addr = low_mask & ((packed & (low_mask << addr_off)) >> addr_off);
  }

  if (burst_len_w) {
    low_mask = ~(1L << (PackedW - 1)) >> (PackedW - 1 - burst_len_w);
    burst_len =
        low_mask & ((packed & (low_mask << burst_len_off)) >> burst_len_off);
  }

  if (burst_size_w) {
    low_mask = ~(1L << (PackedW - 1)) >> (PackedW - 1 - burst_size_w);
    burst_size =
        low_mask & ((packed & (low_mask << burst_size_off)) >> burst_size_off);
  }

  if (burst_type_w) {
    low_mask = ~(1L << (PackedW - 1)) >> (PackedW - 1 - burst_type_w);
    burst_type =
        low_mask & ((packed & (low_mask << burst_type_off)) >> burst_type_off);
  }

  if (lock_type_w) {
    low_mask = ~(1L << (PackedW - 1)) >> (PackedW - 1 - lock_type_w);
    lock_type =
        low_mask & ((packed & (low_mask << lock_type_off)) >> lock_type_off);
  }

  if (memtype_w) {
    low_mask = ~(1L << (PackedW - 1)) >> (PackedW - 1 - memtype_w);
    memtype = low_mask & ((packed & (low_mask << memtype_off)) >> memtype_off);
  }

  if (prot_w) {
    low_mask = ~(1L << (PackedW - 1)) >> (PackedW - 1 - prot_w);
    prot = low_mask & ((packed & (low_mask << prot_off)) >> prot_off);
  }

  if (qos_w) {
    low_mask = ~(1L << (PackedW - 1)) >> (PackedW - 1 - qos_w);
    qos = low_mask & ((packed & (low_mask << qos_off)) >> qos_off);
  }
}

uint64_t WriteAddressRequest::to_packed() {
  uint64_t packed = 0UL;
  uint64_t low_mask;

  if (id_w) {
    low_mask = ~((1L << (PackedW - 1)) >> (PackedW - 1 - id_w));
    packed &= ~(low_mask << id_off);
    packed |= (low_mask & id) << id_off;
  }

  if (addr_w) {
    low_mask = ~((1L << (PackedW - 1)) >> (PackedW - 1 - addr_w));
    packed &= ~(low_mask << addr_off);
    packed |= (low_mask & addr) << addr_off;
  }

  if (burst_len_w) {
    low_mask = ~((1L << (PackedW - 1)) >> (PackedW - 1 - burst_len_w));
    packed &= ~(low_mask << burst_len_off);
    packed |= (low_mask & burst_len) << burst_len_off;
  }

  if (burst_size_w) {
    low_mask = ~((1L << (PackedW - 1)) >> (PackedW - 1 - burst_size_w));
    packed &= ~(low_mask << burst_size_off);
    packed |= (low_mask & burst_size) << burst_size_off;
  }

  if (burst_type_w) {
    low_mask = ~((1L << (PackedW - 1)) >> (PackedW - 1 - burst_type_w));
    packed &= ~(low_mask << burst_type_off);
    packed |= (low_mask & burst_type) << burst_type_off;
  }

  if (lock_type_w) {
    low_mask = ~((1L << (PackedW - 1)) >> (PackedW - 1 - lock_type_w));
    packed &= ~(low_mask << lock_type_off);
    packed |= (low_mask & lock_type) << lock_type_off;
  }

  if (memtype_w) {
    low_mask = ~((1L << (PackedW - 1)) >> (PackedW - 1 - memtype_w));
    packed &= ~(low_mask << memtype_off);
    packed |= (low_mask & memtype) << memtype_off;
  }

  if (prot_w) {
    low_mask = ~(1L << ((PackedW - 1)) >> (PackedW - 1 - prot_w));
    packed &= ~(low_mask << prot_off);
    packed |= (low_mask & prot) << prot_off;
  }

  if (qos_w) {
    low_mask = ~((1L << (PackedW - 1)) >> (PackedW - 1 - qos_w));
    packed &= ~(low_mask << qos_off);
    packed |= (low_mask & qos) << qos_off;
  }

  return packed;
}

////////////////////
// Write response //
////////////////////

// Static constant definition (widths)
const uint64_t WriteResponse::id_w = IDWidth;
const uint64_t WriteResponse::content_w = XRespWidth;

// Static constant definition (offsets)
const uint64_t WriteResponse::id_off = 0UL;
const uint64_t WriteResponse::content_off =
    WriteResponse::id_off + WriteResponse::id_w;

void WriteResponse::from_packed(uint64_t packed) {
  uint64_t low_mask;

  if (id_w) {
    low_mask = ~(1L << (PackedW - 1)) >> (PackedW - 1 - id_w);
    id = low_mask & ((packed & (low_mask << id_off)) >> id_off);
  }

  if (content_w) {
    low_mask = ~(1L << (PackedW - 1)) >> (PackedW - 1 - content_w);
    content = low_mask & ((packed & (low_mask << content_off)) >> content_off);
  }
}

uint64_t WriteResponse::to_packed() {
  uint64_t packed = 0UL;
  uint64_t low_mask;
  if (id_w) {
    low_mask = ~((1L << (PackedW - 1)) >> (PackedW - 1 - id_w));
    packed &= ~(low_mask << id_off);
    packed |= (low_mask & id) << id_off;
  }

  if (content_w) {
    low_mask = ~((1L << (PackedW - 1)) >> (PackedW - 1 - content_w));
    packed &= ~(low_mask << content_off);
    packed |= (low_mask & content) << content_off;
  }

  return packed;
}