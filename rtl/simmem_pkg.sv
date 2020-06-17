// Copyright lowRISC contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0
//
// simmem package

package simmem_pkg;

  typedef enum logic {
    READ_REQ = 1'b0,
    WRITE_RESP = 1'b1
  } data_channel_e;

  typedef enum logic {
    READ_DATA = 1'b0,
    WRITE_RESP = 1'b1
  } bank_channel_e;

  typedef enum logic {
    STRUCT_RAM = 1'b0,
    NEXT_ELEM_RAM = 1'b1
  } ram_bank_e;

  typedef enum logic {
    RAM_IN = 1'b0,
    RAM_OUT = 1'b1
  } ram_port_e;

endpackage
