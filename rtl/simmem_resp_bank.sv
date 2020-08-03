// Copyright lowRISC contributors. Licensed under the Apache License, Version 2.0, see LICENSE for
// details. SPDX-License-Identifier: Apache-2.0
//
// Linked list bank for responses in the simulated memory controller with burst support

// Response banks provide a multi-FIFO storage with reservation functionality for responses coming
// from the real memory controller. The FIFOs are implemented as linked lists, sharing the same
// memory space.
//
// Response structure: The term 'response' is used to refer to the AXI response coming back from the
//  real memory controller, excluding handshake signals. Each response starts with an AXI identifier
//  of a specific length IDWidth (on the LSB side). The rest of the response bits is referred to as
//  'payload'. As there is one linked list per AXI identifier, only the payload is stored in RAM.
//
// A response bank uses three RAMs:
//  * The payload RAM, containing the response response payloads.
//  * The metadata RAM, containing pointers that form the concurrent linked lists (there is one
//    linked list per AXI identifier). The metadata RAM is duplicated to make concurrent input and
//    output possible.
//
// Linked list implementation: Each linked list is supported by four pointers, which, outside of
//   corner cases, can be described as follows: 
//  * Reservation head (rsv_heads_q): Points to the last reserved address.
//  * Response head (rsp_heads): Points to the next RAM address where a payload of the corresponding
//    AXI identifier will be stored.
//  * Pre_tail (pre_tails): Points to the second-to-last cell hosting a response in the linked list.
//  * Tail (tails): Points to the last cell hosting a response in the linked list.
//
//  The order of the pointers must always be respected. They can be equal but never overtake each
//    other, in the order defined by the linked list.
//
// Reservation flow: When the reservation handshake succeeds, a new RAM cell is reserved and the
//  corresponding address is advertised, as it is externally used as a request/response identifier.
//  The reservation head pointer of the corresponding head is moved to the next free RAM entry, and
//  the corresponding linked list pointer (which links the current reservation head to the new
//  reservation head address) is written into the metadata RAM.
//
// Response input flow: When the input handshake succeeds, the RAM cell pointed by the response head
//  of the corresponding AXI identifier stores the response payload. The response head pointer
//  follows the pointer in the metadata RAM (except for some corner cases).
//
// Response output flow: When the output handshake succeeds, the RAM output is transmitted to the
//  requester. The pre_tail pointer follows the pointer in the metadata RAM and the tail takes the
//  value of the pre_tail (except for some corner cases)
//
// Tail vs. pre_tail: Two distinct tail pointers are required to dynamically manage the two
//  following cases:
//    * The pre_tail address is given as input to the payload RAM if there is a successful output
//      handshake and the value at the output has an AXI id corresponding to the AXI id of the
//      considered linked list. It must point to:
//      - The second-to-last element of the linked list if the list contains two reponses or more,
//      - The last element element of the linked list if the list contains just one response,
//      - rsp_head if the list contains no responses.

//    * The tail address is given as input to the payload RAM in all other cases. This case
//      disjunction prevents an output data from being output twice, and prevents any bandwidth drop
//      at the output. It must point to:
//      - The last element element of the linked list if the list contains one response or more,
//      - pre_tail if the list contains no responses.
//
//  Corner cases and vector piggybacking: Several corner cases appear when linked list pointers
//    cannot be updated in the regular way. In this case, a process called pointer piggybacking is
//    implemented. For two pointers a and b, the signal 'pgbk_a_with_b' or 'pgbk_a_with_b_q' means,
//    at level 1'b1, that if the pointer b is updated during the current clock cycle, then the
//    pointer a must be updated with the same value. Piggyback is a lazy operation (in the sense
//    that if the pointer b is not updated, then a remains untouched as well) that maintains the
//    pointer ordering.

module simmem_resp_bank #(
    parameter int unsigned MaxBurstLen = 4,
    parameter int unsigned TotCapa = simmem_pkg::ReadDataBankCapacity,
    parameter type DataType = simmem_pkg::rdata_t,

    localparam int unsigned BurstLenWidth = $clog2 (MaxBurstLen + 1),  // derived parameter
    localparam int unsigned BankAddrWidth = $clog2 (TotCapa),  // derived parameter
    localparam int unsigned DataWidth = $bits (DataType)  // derived parameter
) (
  input logic clk_i,
  input logic rst_ni,

  // Reservation interface AXI identifier for which the reseration request is being done.
  input  logic [simmem_pkg::NumIds-1:0] rsv_req_id_onehot_i,
  // Information about currently reserved address. Will be stored by other modules as an internal
  // identifier to uniquely identify the response (or response burst in case of read data).
  output logic [BankAddrWidth-1:0] rsv_addr_o,
  // The number of data elements to reserve in the RAM cell.
  input  logic [BurstLenWidth-1:0] rsv_burst_len_i,
  // Reservation handshake signals
  input  logic rsv_valid_i,
  output logic rsv_ready_o, 

  // Interface with the releaser Multi-hot signal that enables the release for given internal
  // addresses (i.e., RAM addresses).
  input  logic [TotCapa-1:0] release_en_i,
  // Signals which address has been released, if any. One-hot signal. Is set to one for each
  // released response in a burst.
  output logic [TotCapa-1:0] released_addr_onehot_o,

  // Interface with the real memory controller AXI response excluding handshake
  input  DataType rsp_i,
  output DataType rsp_o,
  // Response acquisition handshake signal
  input  logic in_rsp_valid_i,
  output logic in_rsp_ready_o,

  // Interface with the requester
  input  logic out_rsp_ready_i,
  output logic out_rsp_valid_o
);

  import simmem_pkg::*;

  localparam int PayloadWidth = DataWidth - IDWidth;
  localparam int PayloadRamWidth = MaxBurstLen * PayloadWidth;

  typedef struct packed {logic [BankAddrWidth-1:0] nxt_elem;} metadata_e;


  //////////////////
  // RAM pointers //
  //////////////////

  //  In this part, the linked list related pointers are declared and updated.
  //
  //  Response heads: 
  //    * rsp_heads_d, rsp_heads_q: Next response head, except if the response head will be updated
  //      from RAM.
  //    * rsp_heads: The actual current response head, after potential update from RAM.
  //
  //  Reservation heads:
  //    * rsv_heads_d: Next reservation head.
  //    * rsv_heads_q: The actual current reservation head.
  //
  //  Tails:
  //    * tails_d, tails_q: Next tail, except that it does not take piggyback with the response head
  //      pointer into account.
  //    * tails: The actual tail.
  //
  //  Pre_tails:
  //    * pre_tails_d, pre_tails_q: Next pre_tail, except that it does not take piggyback with the
  //      response head pointer into account.
  //    * pre_tails: The actual current tail.
  //
  //  Linked list lengths: Linked list lengths are maintained, as they help treat corner cases where
  //  lined list pointers are close to each other in the linked list:
  //    * rsv_len_d, rsv_len_q: The number of entries reserved in the linked list, that are not
  //      occupied by responses yet.
  //    * rsp_len_d, rsp_len_q: The number of RAM cells in the linked list that contain responses.
  //    * rsp_len_after_out: The number of RAM cells in the linked list that contain responses,
  //      minus one if one of the cells is currently being output.
  //
  //  Miscellaneous signals: Some additional signals are required to smoothly treat corner cases.
  //    * queue_initiated: The linked list is called initiated if the reservation is made for this
  //      identifier, and if there is at least one reserved cell in the queue or there will be at
  //      least one actual stored element in the queue after the possible output.
  //    * is_rsp_head_emptybox_d, is_rsp_head_emptybox_q: The response head pointer is said to point
  //      to an empty box if it has the same value as the reservation head, but the targeted RAM
  //      cell does not contain any response yet.

  // Head, tail and length signals

  logic [BankAddrWidth-1:0] rsp_heads_d[NumIds];
  logic [BankAddrWidth-1:0] rsp_heads_q[NumIds];
  logic [BankAddrWidth-1:0] rsp_heads[NumIds];  // Effective response head, after update from RAM

  logic [BankAddrWidth-1:0] rsv_heads_d[NumIds];
  logic [BankAddrWidth-1:0] rsv_heads_q[NumIds];

  logic [BankAddrWidth-1:0] tails_d[NumIds];
  logic [BankAddrWidth-1:0] tails_q[NumIds];
  logic [BankAddrWidth-1:0] tails[NumIds];  // Effective pointer, after piggyback with response

  logic [BankAddrWidth-1:0] pre_tails_d[NumIds];
  logic [BankAddrWidth-1:0] pre_tails_q[NumIds];
  logic [BankAddrWidth-1:0] pre_tails[NumIds];

  // Piggyback signals translate that if the piggybacker gets updated in the next cycle, then follow
  // it. They serve the many corner cases where regular update from the RAM or from the current
  // value of the pointer ahead (in the case of the pre_tails) is not possible. Abbreviations are:
  //  * rsv: Reservation head
  //  * rsp: Response head head
  //  * pt: Pre_tail
  //  * t: Tail
  logic pgbk_rsp_with_rsv[NumIds];
  logic pgbk_t_with_rsv[NumIds];
  logic pgbk_pt_with_rsv[NumIds];
  logic pgbk_t_with_rsp_d[NumIds];
  logic pgbk_t_with_rsp_q[NumIds];
  logic pgbk_pt_with_rsp_d[NumIds];
  logic pgbk_pt_with_rsp_q[NumIds];

  // Update signals are used to update pointers regular operation, following the linked list order.
  logic update_t_from_pt[NumIds];
  logic update_pt_from_ram_q[NumIds];
  logic update_pt_from_ram_d[NumIds];
  logic update_rsp_from_ram_d[NumIds];
  logic update_rsp_from_ram_q[NumIds];
  logic update_rsv_heads[NumIds];

  logic [NumIds-1:0] queue_initiated;

  logic is_rsp_head_emptybox_d[NumIds];
  logic is_rsp_head_emptybox_q[NumIds];

  // Lengths of reservation and response queues.
  logic [BankAddrWidth-1:0] rsv_len_d[NumIds];
  logic [BankAddrWidth-1:0] rsv_len_q[NumIds];

  logic [BankAddrWidth-1:0] rsp_len_d[NumIds];
  logic [BankAddrWidth-1:0] rsp_len_q[NumIds];

  // Length after the potential output.
  logic [BankAddrWidth-1:0] rsp_len_after_out[NumIds];

  // Update heads, rsp_heads and pre_tails according to the piggyback and update signals.
  for (genvar i_id = 0; i_id < NumIds; i_id = i_id + 1) begin : pointers_update
    assign rsp_heads_d[i_id] = pgbk_rsp_with_rsv[i_id] ? rsv_heads_d[i_id] : rsp_heads[i_id];
    assign rsp_heads[i_id] =
        update_rsp_from_ram_q[i_id] ? meta_ram_out_rsp_head.nxt_elem : rsp_heads_q[i_id];

    always_comb begin
      // The next tail is either piggybacked with the head, or follows the pre_tail, or keeps its
      // value. If it is piggybacked by the response head pointer, then the update is done in the
      // next cycle.
      if (pgbk_t_with_rsv[i_id]) begin
        tails_d[i_id] = nxt_free_addr;
      end else if (update_t_from_pt[i_id]) begin
        tails_d[i_id] = pre_tails[i_id];
      end else begin
        tails_d[i_id] = tails[i_id];
      end
    end
    assign tails[i_id] = pgbk_t_with_rsp_q[i_id] ? rsp_heads[i_id] : tails_q[i_id];

    assign pre_tails_d[i_id] = pgbk_pt_with_rsv[i_id] ? rsv_heads_d[i_id] : pre_tails[i_id];
    always_comb begin
      if (pgbk_pt_with_rsp_q[i_id]) begin
        pre_tails[i_id] = rsp_heads[i_id];
      end else if (update_pt_from_ram_q[i_id]) begin
        pre_tails[i_id] = meta_ram_out_rsp_tail.nxt_elem;
      end else begin
        pre_tails[i_id] = pre_tails_q[i_id];
      end
    end

    assign rsv_heads_d[i_id] = update_rsv_heads[i_id] ? nxt_free_addr : rsv_heads_q[i_id];
  end


  /////////////////////////
  // Burst count in cell //
  /////////////////////////

  //  This part is dedicated to counting the burst elements in a RAM cell.
  //
  //  Counters:
  //    * rsv_cnt_d, rsv_cnt_q: Count the elements reserved but not acquired yet in a given RAM
  //      address. The counters are set at reservation time and decreased when responses are stored
  //      in the corresponding cell.
  //    * rsp_cnt_d, rsp_cnt_q: Count the elements contained in a given RAM address. The counters
  //      are increased when responses are acquired and decreased when data is released.
  //
  //  Counters are updated using three masks:
  //    * cnt_rsv_mask: contains at most one bit to one, where a new reservation is performed.
  //    * cnt_in_mask: contains at most one bit to one, where a response is accepted. This mask is
  //      collaboratively built by all linkedlists using the signals cnt_in_mask_id.
  //    * cnt_out_mask: contains at most one bit to one, where a response is released.
  //
  //  Per-linked list counters: Each linked list has its own counters to track how many responses
  //  are in certain cells. These are not new physical counters. Instead, they base on rsv_cnt and
  //  rsp_cnt counters. Each linked list has the following logical counters:
  //    * rsv_cnt_id: Tracks the number of responses reserved but not acquired yet in the RAM cell
  //      pointed by the response head pointer. This is useful to track when to update the rsp_head
  //      pointer.
  //    * rsp_cnt_id: Tracks the number of responses contained under the response head pointer. This
  //      is useful to set the input mask of the payload RAM.
  //    * pre_tail_cnt_id: Tracks the number of responses contained under the pre_tail pointer. This
  //      is useful to set the output mask of the payload RAM.
  //    * tail_cnt_id: Tracks the number of responses contained under the tail pointer. This is
  //      useful to set the output mask of the payload RAM.

  logic [BurstLenWidth-1:0] rsv_cnt_d[TotCapa];
  logic [BurstLenWidth-1:0] rsv_cnt_q[TotCapa];
  logic [BurstLenWidth-1:0] rsp_cnt_d[TotCapa];
  logic [BurstLenWidth-1:0] rsp_cnt_q[TotCapa];

  logic [TotCapa-1:0] cnt_rsv_mask;
  logic [TotCapa-1:0][NumIds-1:0] cnt_in_mask_id;
  logic cnt_in_mask[TotCapa];
  logic [TotCapa-1:0] cnt_out_mask;

  for (genvar i_addr = 0; i_addr < TotCapa; i_addr = i_addr + 1) begin : cnt_update

    // A reservation mask bit is set to one if there is a successful reservation handshake and this
    // bit corresponds to the next address to reserve (i.e., the next free address).
    assign cnt_rsv_mask[i_addr] = nxt_free_addr == i_addr && rsv_ready_o && rsv_valid_i;

    // An output mask bit is set to one if there is a successful output handshake and this bit
    // corresponds to address of the data at the output.
    assign
        cnt_out_mask[i_addr] = cur_out_addr_onehot_q[i_addr] && out_rsp_valid_o && out_rsp_ready_i;

    for (genvar i_id = 0; i_id < NumIds; i_id = i_id + 1) begin : gen_cnt_in_mask
      // Here is looked at which address the incoming response would land, if there were an incoming
      // response.
      assign cnt_in_mask_id[i_addr][i_id] =
          rsp_i.merged_payload.id == i_id && rsp_heads[i_id] == i_addr;
    end : gen_cnt_in_mask
    // Using the previous information, aggregated among all linked lists, we set the corresponding
    // bit to one if there is actually an incoming response.
    assign cnt_in_mask[i_addr] = in_rsp_ready_o && in_rsp_valid_i && |cnt_in_mask_id[i_addr];

    always_comb begin
      rsv_cnt_d[i_addr] = rsv_cnt_q[i_addr];
      rsp_cnt_d[i_addr] = rsp_cnt_q[i_addr];

      // Update the counters according to the masks
      if (cnt_rsv_mask[i_addr]) begin
        rsv_cnt_d[i_addr] = rsv_burst_len_i;
      end else if (cnt_in_mask[i_addr]) begin
        rsv_cnt_d[i_addr] = rsv_cnt_q[i_addr] - 1;
        rsp_cnt_d[i_addr] = rsp_cnt_q[i_addr] + 1;
      end
      if (cnt_out_mask[i_addr]) begin
        rsp_cnt_d[i_addr] = rsp_cnt_q[i_addr] - 1;
      end
    end
  end : cnt_update
  assign released_addr_onehot_o = cnt_out_mask;

  // Intermediate signals to calculate counts
  logic [TotCapa-1:0][BurstLenWidth-1:0] rsv_cnt_addr[NumIds];
  logic [TotCapa-1:0][BurstLenWidth-1:0] rsp_cnt_addr[NumIds];
  logic [TotCapa-1:0][BurstLenWidth-1:0] pre_tail_cnt_addr[NumIds];
  logic [TotCapa-1:0][BurstLenWidth-1:0] tail_cnt_addr[NumIds];
  // Intermediate aggregation signals
  logic [BurstLenWidth-1:0][TotCapa-1:0] rsv_cnt_addr_rot90[NumIds];
  logic [BurstLenWidth-1:0][TotCapa-1:0] rsp_cnt_addr_rot90[NumIds];
  logic [BurstLenWidth-1:0][TotCapa-1:0] pre_tail_cnt_addr_rot90[NumIds];
  logic [BurstLenWidth-1:0][TotCapa-1:0] tail_cnt_addr_rot90[NumIds];
  // Actual counts per linked list
  logic [BurstLenWidth-1:0] rsv_cnt_id[NumIds];
  logic [BurstLenWidth-1:0] rsp_cnt_id[NumIds];
  logic [BurstLenWidth-1:0] pre_tail_cnt_id[NumIds];
  logic [BurstLenWidth-1:0] tail_cnt_id[NumIds];

  // Assign the count intermediate signals
  for (genvar i_id = 0; i_id < NumIds; i_id = i_id + 1) begin : gen_cnt
    for (genvar i_addr = 0; i_addr < TotCapa; i_addr = i_addr + 1) begin : gen_cnt_addr
      assign rsv_cnt_addr[i_id][i_addr] =
          rsv_cnt_q[i_addr] & {BurstLenWidth{rsp_heads[i_id] == i_addr && |rsv_len_q[i_id]}};
      assign rsp_cnt_addr[i_id][i_addr] = rsp_cnt_q[i_addr] & {
          BurstLenWidth{rsp_heads[i_id] == i_addr && (|rsv_len_q[i_id] || |rsp_len_q[i_id])}};
      assign pre_tail_cnt_addr[i_id][i_addr] =
          rsp_cnt_q[i_addr] & {BurstLenWidth{pre_tails[i_id] == i_addr}};
      assign
          tail_cnt_addr[i_id][i_addr] = rsp_cnt_q[i_addr] & {BurstLenWidth{tails[i_id] == i_addr}};

      for (genvar i_bit = 0; i_bit < BurstLenWidth; i_bit = i_bit + 1) begin : gen_cnt_addr_rot
        assign rsv_cnt_addr_rot90[i_id][i_bit][i_addr] = rsv_cnt_addr[i_id][i_addr][i_bit];
        assign rsp_cnt_addr_rot90[i_id][i_bit][i_addr] = rsp_cnt_addr[i_id][i_addr][i_bit];
        assign
            pre_tail_cnt_addr_rot90[i_id][i_bit][i_addr] = pre_tail_cnt_addr[i_id][i_addr][i_bit];
        assign tail_cnt_addr_rot90[i_id][i_bit][i_addr] = tail_cnt_addr[i_id][i_addr][i_bit];
      end : gen_cnt_addr_rot
    end : gen_cnt_addr

    for (genvar i_bit = 0; i_bit < BurstLenWidth; i_bit = i_bit + 1) begin : gen_cnt_after_rot
      assign rsv_cnt_id[i_id][i_bit] = |rsv_cnt_addr_rot90[i_id][i_bit];
      assign rsp_cnt_id[i_id][i_bit] = |rsp_cnt_addr_rot90[i_id][i_bit];
      assign pre_tail_cnt_id[i_id][i_bit] = |pre_tail_cnt_addr_rot90[i_id][i_bit];
      assign tail_cnt_id[i_id][i_bit] = |tail_cnt_addr_rot90[i_id][i_bit];
    end : gen_cnt_after_rot
  end : gen_cnt


  ///////////////
  // RAM valid //
  ///////////////

  // RAM addresses are said valid iff the corresponding reservation or response counter is not zero.
  // In simple words, it means that the address has either reserved space or contains some data (or
  // both).

  logic [TotCapa-1:0] ram_v;

  for (genvar i_addr = 0; i_addr < TotCapa; i_addr = i_addr + 1) begin : ram_v_update
    assign ram_v[i_addr] = |rsp_cnt_q[i_addr] || |rsv_cnt_q[i_addr];
  end : ram_v_update


  /////////////////////////
  // Next free RAM entry //
  /////////////////////////

  //  In this part, the free RAM entry of lowest address is found. It is used to update the
  //  reservation head in casae of reservation handshake.
  //
  //  Two signals are used:
  //  * nxt_free_addr_onehot: A one-hot signal indicating the next free entry in the RAM. Can be
  //    full-zero if no entry is free in the RAM.
  //  * nxt_free_addr: The corresponding binary signal.

  // Find the next free address and transform next free address from one-hot to binary encoding
  logic nxt_free_addr_onehot[TotCapa];  // Can be full zero
  logic [BankAddrWidth-1:0] nxt_free_addr;

  // Genereate the next free address onehot signal
  for (genvar i_addr = 0; i_addr < TotCapa; i_addr = i_addr + 1) begin : gen_nxt_free_addr_onehot
    if (i_addr == 0) begin
      assign nxt_free_addr_onehot[0] = ~ram_v[0];
    end else begin
      assign nxt_free_addr_onehot[i_addr] = ~ram_v[i_addr] && &ram_v[i_addr - 1:0];
    end
  end : gen_nxt_free_addr_onehot

  // Get the next free address binary signal from the corresponding onehot signal
  always_comb begin
    nxt_free_addr = '0;
    for (int unsigned i_addr = 0; i_addr < TotCapa; i_addr = i_addr + 1) begin
      if (nxt_free_addr_onehot[i_addr]) begin
        nxt_free_addr = i_addr[BankAddrWidth - 1:0];
      end
    end
  end

  assign rsv_addr_o = nxt_free_addr;


  ////////////////////////////
  // RAM management signals //
  ////////////////////////////

  //  In this part, RAM management signals are declared and treated.
  //
  //  RAM access patterns:
  //    * On reservation handshake, write to metadata RAMs.
  //    * On input handshake, read from response head metadata RAM and write to payload RAM.
  //    * On output handshake, read from tail metadata RAM and read from payload RAM.
  //
  //  Some signals are set globally, and others are aggregated from all linked lists. The latter
  //  are:
  //    * pyld_ram_in_addr_id,     as the address should be the response head pointer value.
  //    * pyld_ram_out_addr_id,    as the address should be the pre_tail or tail pointer value.
  //    * meta_ram_in_addr_id,        as the address may be the reservation head pointer value.
  //    * meta_ram_out_addr_tail_id,  as the address should be the tail pointer value.
  //    * meta_ram_out_addr_rsp_head_id,   as the address should be the response head pointer value.
  //
  //  Rotated signals are used to aggregate the signals, where the dimensions have to be transposed.
  //
  // Mask generation: The payload RAM write masks (pyld_ram_in_wmask and
  // pyld_ram_out_wmask_d) are generated based on the response counters. The
  // output mask must be registered, because it is calculated in the clock cycle before
  // the output data is available.
  //
  //  Mask expansion: As the RAMs require masks as wide as the data words, payload RAM masks are
  //  expanded to fit with the required format.
  //
  //  Payload RAM input and output data: The input data (pyld_ram_in_burst_data) is the input
  //  payload repeated periodically. The mask indicates the location of the data. The output data
  //  (pyld_ram_burst_data) is extracted from the payload RAM data from the payload RAM
  //  (pyld_ram_out_burst_data) using the mask information.

  logic pyld_ram_in_req, pyld_ram_out_req;
  logic meta_ram_in_req, meta_ram_out_req;

  logic pyld_ram_in_write, pyld_ram_out_write;
  logic meta_ram_in_write, meta_ram_out_write;

  logic [MaxBurstLen-1:0] pyld_ram_in_wmask;
  logic [MaxBurstLen-1:0] pyld_ram_out_wmask_d, pyld_ram_out_wmask_q;
  logic [MaxBurstLen-1:0] pyld_ram_in_wmask_id[NumIds];
  logic [MaxBurstLen-1:0] pyld_ram_out_wmask_id[NumIds];
  logic [MaxBurstLen-1:0][NumIds-1:0] pyld_ram_in_wmask_id_rot90;
  logic [MaxBurstLen-1:0][NumIds-1:0] pyld_ram_out_wmask_id_rot90;
  // The signal to be provided to the payload RAM, which requires the wmask to be as long as the
  // data.
  logic [PayloadRamWidth-1:0] pyld_ram_in_wmask_expanded;
  logic [PayloadRamWidth-1:0] pyld_ram_out_wmask_expanded;

  logic [BankAddrWidth-1:0] meta_ram_in_wmask, meta_ram_out_wmask;

  metadata_e meta_ram_in_content;
  metadata_e meta_ram_in_content_id[NumIds];
  logic [NumIds - 1:0] meta_ram_in_content_msk_rot90[BankAddrWidth];

  // Aggregate the read/write masks
  for (genvar i_id = 0; i_id < NumIds; i_id = i_id + 1) begin : aggregate_wmask_id
    for (genvar i_bit = 0; i_bit < MaxBurstLen; i_bit = i_bit + 1) begin : aggregate_wmask_id_rot
      assign pyld_ram_in_wmask_id_rot90[i_bit][i_id] = pyld_ram_in_wmask_id[i_id][i_bit];
      assign pyld_ram_out_wmask_id_rot90[i_bit][i_id] = pyld_ram_out_wmask_id[i_id][i_bit];
    end : aggregate_wmask_id_rot
  end : aggregate_wmask_id
  for (genvar i_bit = 0; i_bit < MaxBurstLen; i_bit = i_bit + 1) begin : aggregate_wmask
    assign pyld_ram_in_wmask[i_bit] = |pyld_ram_in_wmask_id_rot90[i_bit];
    assign pyld_ram_out_wmask_d[i_bit] = |pyld_ram_out_wmask_id_rot90[i_bit];
  end : aggregate_wmask

  metadata_e meta_ram_out_rsp_tail, meta_ram_out_rsp_head;

  // RAM address and aggregation
  logic [BankAddrWidth-1:0] pyld_ram_in_addr;
  logic [BankAddrWidth-1:0] pyld_ram_out_addr;
  logic [BankAddrWidth-1:0] meta_ram_in_addr;
  logic [BankAddrWidth-1:0] meta_ram_out_addr_tail;
  logic [BankAddrWidth-1:0] meta_ram_out_addr_rsp_head;
  // Per-linked list intermediate signals
  logic [BankAddrWidth-1:0] pyld_ram_in_addr_id[NumIds];
  logic [BankAddrWidth-1:0] pyld_ram_out_addr_id[NumIds];
  logic [BankAddrWidth-1:0] meta_ram_in_addr_id[NumIds];
  logic [BankAddrWidth-1:0] meta_ram_out_addr_tail_id[NumIds];
  logic [BankAddrWidth-1:0] meta_ram_out_addr_rsp_head_id[NumIds];
  // Intermediate aggregation signal
  logic [BankAddrWidth-1:0][NumIds-1:0] pyld_ram_in_addr_rot90;
  logic [BankAddrWidth-1:0][NumIds-1:0] pyld_ram_out_addr_rot90;
  logic [BankAddrWidth-1:0][NumIds-1:0] meta_ram_in_addr_rot90;
  logic [BankAddrWidth-1:0][NumIds-1:0] meta_ram_out_addr_tail_rot90;
  logic [BankAddrWidth-1:0][NumIds-1:0] meta_ram_out_addr_rsp_head_rot90;

  // RAM address aggregation
  for (genvar i_id = 0; i_id < NumIds; i_id = i_id + 1) begin : rotate_ram_address
    for (
        genvar i_bit = 0; i_bit < BankAddrWidth; i_bit = i_bit + 1
    ) begin : rotate_ram_address_inner
      assign pyld_ram_in_addr_rot90[i_bit][i_id] = pyld_ram_in_addr_id[i_id][i_bit];
      assign pyld_ram_out_addr_rot90[i_bit][i_id] = pyld_ram_out_addr_id[i_id][i_bit];
      assign meta_ram_in_addr_rot90[i_bit][i_id] = meta_ram_in_addr_id[i_id][i_bit];
      assign meta_ram_out_addr_tail_rot90[i_bit][i_id] = meta_ram_out_addr_tail_id[i_id][i_bit];
      assign meta_ram_out_addr_rsp_head_rot90[i_bit][i_id] =
          meta_ram_out_addr_rsp_head_id[i_id][i_bit];
    end : rotate_ram_address_inner
  end : rotate_ram_address
  for (genvar i_bit = 0; i_bit < BankAddrWidth; i_bit = i_bit + 1) begin : aggregate_ram_address
    assign pyld_ram_in_addr[i_bit] = |pyld_ram_in_addr_rot90[i_bit];
    assign pyld_ram_out_addr[i_bit] = |pyld_ram_out_addr_rot90[i_bit];
    assign meta_ram_in_addr[i_bit] = |meta_ram_in_addr_rot90[i_bit];
    assign meta_ram_out_addr_tail[i_bit] = |meta_ram_out_addr_tail_rot90[i_bit];
    assign meta_ram_out_addr_rsp_head[i_bit] = |meta_ram_out_addr_rsp_head_rot90[i_bit];
  end : aggregate_ram_address

  // RAM meta in aggregation
  for (genvar i_id = 0; i_id < NumIds; i_id = i_id + 1) begin : rotate_meta_in
    for (genvar i_bit = 0; i_bit < BankAddrWidth; i_bit = i_bit + 1) begin : rotate_meta_in_inner
      assign meta_ram_in_content_msk_rot90[i_bit][i_id] = meta_ram_in_content_id[i_id][i_bit];
    end : rotate_meta_in_inner
  end : rotate_meta_in
  for (genvar i_bit = 0; i_bit < BankAddrWidth; i_bit = i_bit + 1) begin : aggregate_meta_in
    assign meta_ram_in_content[i_bit] = |meta_ram_in_content_msk_rot90[i_bit];
  end : aggregate_meta_in

  // RAM write masks, filled with ones
  assign meta_ram_in_wmask = {BankAddrWidth{1'b1}};
  assign meta_ram_out_wmask = {BankAddrWidth{1'b1}};

  // Payload RAM wmask extension
  for (genvar i_bur = 0; i_bur < MaxBurstLen; i_bur = i_bur + 1) begin : expand_rsp_wmasks
    for (
        genvar i_bit = PayloadWidth * i_bur; i_bit < PayloadWidth * (i_bur + 1); i_bit = i_bit + 1
    ) begin : expand_rsp_wmasks_inner
      assign pyld_ram_in_wmask_expanded[i_bit] = pyld_ram_in_wmask[i_bur];
      assign pyld_ram_out_wmask_expanded[i_bit] = pyld_ram_out_wmask_d[i_bur];
    end : expand_rsp_wmasks_inner
  end : expand_rsp_wmasks

  // RAM request signals The payload RAM input is triggered iff there is a successful data input
  // handshake
  assign pyld_ram_in_req = in_rsp_ready_o && in_rsp_valid_i;

  // The payload RAM output is triggered iff there is data to output at the next cycle
  assign pyld_ram_out_req = |nxt_id_to_release_onehot;

  // Assign the queue_initiated signal, to compute whether the metadata RAM should be requested
  for (genvar i_id = 0; i_id < NumIds; i_id = i_id + 1) begin : req_meta_in_id_assignment
    // The queue is called initiated if the reservation is made for this identifier, and the length
    // condition is satisfied, namely if there is at least one reserved cell in the queue or there
    // will be at least one actual stored element in the queue after the possible output.
    assign queue_initiated[i_id] =
        rsv_req_id_onehot_i[i_id] && (|rsv_len_q[i_id] || |rsp_len_after_out[i_id]);
  end : req_meta_in_id_assignment

  // New metadata input is coming when there is a reservation and the queue is already initiated
  assign meta_ram_in_req = rsv_valid_i && rsv_ready_o && |queue_initiated;

  // Metadata output is requested when there is output to be released (to potentially update the
  // corresponding pre_tails from RAM) or input data coming (to potentially update the corresponding
  // response head pointer from RAM). 
  always_comb begin
    meta_ram_out_req = 1'b0;
    for (int unsigned i_id = 0; i_id < NumIds; i_id = i_id + 1) begin
      meta_ram_out_req |= update_rsp_from_ram_d[i_id] | update_pt_from_ram_d[i_id];
    end
  end

  assign pyld_ram_in_write = pyld_ram_in_req;
  assign pyld_ram_out_write = 1'b0;
  assign meta_ram_in_write = meta_ram_in_req;
  assign meta_ram_out_write = 1'b0;

  // Response RAM input and output data selection
  logic [MaxBurstLen-1:0][DataWidth-IDWidth-1:0] pyld_ram_in_burst_data;
  logic [MaxBurstLen-1:0][DataWidth-IDWidth-1:0] pyld_ram_out_burst_data;
  logic [DataWidth-IDWidth-1:0][MaxBurstLen-1:0] pyld_ram_out_burst_data_rot90;
  logic [DataWidth-IDWidth-1:0] pyld_ram_out_data;


  // Fill input with the input payload. The irrelevant input will be filtered out using the wmasks.
  for (genvar i_bur = 0; i_bur < MaxBurstLen; i_bur = i_bur + 1) begin : gen_pyld_input
    assign pyld_ram_in_burst_data[i_bur] = rsp_i.merged_payload.payload;
  end : gen_pyld_input

  // Output payload.
  for (genvar i_bit = 0; i_bit < PayloadWidth; i_bit = i_bit + 1) begin : gen_out_data
    for (genvar i_bur = 0; i_bur < MaxBurstLen; i_bur = i_bur + 1) begin : gen_out_rsp_inner
      assign pyld_ram_out_burst_data_rot90[i_bit][i_bur] =
          pyld_ram_out_burst_data[i_bur][i_bit] & pyld_ram_out_wmask_q[i_bur];
    end : gen_out_rsp_inner
    assign pyld_ram_out_data[i_bit] = |pyld_ram_out_burst_data_rot90[i_bit];
  end : gen_out_data


  ////////////////////////////////////
  // Next AXI identifier to release //
  ////////////////////////////////////

  //  In this part, the next AXI identifier and address to release is computed.
  //
  //  Involved signals are, in order of dependency:
  //    * nxt_addr_mhot_id: Next addresses to release, multihot and by AXI identifier. Depend on the
  //      input from delay bank and from the response length after output.
  //    * nxt_addr_onehot_id:  Next address to release, onehot and by AXI identifier.
  //    * nxt_id_mhot: Next address to release, multihot.
  //    * nxt_id_mhot: Result signal, indicating in a one-hot fashion, which AXI identifier to
  //      release next. Can be full zero.
  //    * nxt_addr_onehot_rot: Next address to release, one-hot, rotated and filtered by next id to
  //      release. Useful for output calculation below.


  logic [NumIds-1:0][TotCapa-1:0] nxt_addr_mhot_id;
  logic [TotCapa-1:0][NumIds-1:0] nxt_addr_onehot_rot;
  logic [TotCapa-1:0] nxt_addr_onehot_id[NumIds];
  logic [NumIds-1:0] nxt_id_mhot;
  logic [NumIds-1:0] nxt_id_to_release_onehot;

  // Next id and address to release from RAM
  for (genvar i_id = 0; i_id < NumIds; i_id = i_id + 1) begin : gen_next_id

    // Calculation of the next address to release
    for (genvar i_addr = 0; i_addr < TotCapa; i_addr = i_addr + 1) begin : gen_next_addr
      always_comb begin
        // Fundamentally, the next address to release needs to belong to a non-empty AXI identifier
        // and must be enabled for release
        nxt_addr_mhot_id[i_id][i_addr] = |(rsp_len_after_out[i_id]) && release_en_i[i_addr];

        // The address must additionally be, depending on the situation, the pre_tail or the tail of the
        // corresponding queue
        if (out_rsp_ready_i && out_rsp_valid_o && cur_out_id_onehot[i_id] && tail_cnt_id[i_id] == 1
            ) begin
          nxt_addr_mhot_id[i_id][i_addr] &= pre_tails[i_id] == i_addr;
        end else begin
          nxt_addr_mhot_id[i_id][i_addr] &= tails[i_id] == i_addr;
        end
      end

      // Derive onehot from multihot signal
      if (i_addr == 0) begin
        assign nxt_addr_onehot_id[i_id][i_addr] = nxt_addr_mhot_id[i_id][i_addr];
      end else begin
        assign nxt_addr_onehot_id[i_id][i_addr] =
            nxt_addr_mhot_id[i_id][i_addr] && ~|(nxt_addr_mhot_id[i_id][i_addr - 1:0]);
      end
      assign nxt_addr_onehot_rot[i_addr][i_id] =
          nxt_addr_onehot_id[i_id][i_addr] && nxt_id_to_release_onehot[i_id];
    end : gen_next_addr

    // Derive multihot next id to release from next address to release
    assign nxt_id_mhot[i_id] = |nxt_addr_onehot_id[i_id];

    // Derive onehot from multihot signal
    if (i_id == 0) begin
      assign nxt_id_to_release_onehot[i_id] = nxt_id_mhot[i_id];
    end else begin
      assign nxt_id_to_release_onehot[i_id] = nxt_id_mhot[i_id] && ~|(nxt_id_mhot[i_id - 1:0]);
    end
  end : gen_next_id

  // Signals indicating if there is reserved space for a given AXI identifier
  logic [NumIds-1:0] is_id_rsvd;
  for (genvar i_id = 0; i_id < NumIds; i_id = i_id + 1) begin : gen_is_id_reserved
    assign is_id_rsvd[i_id] = rsp_i.merged_payload.id == i_id && |(rsv_len_q[i_id]);
  end : gen_is_id_reserved

  // Input is ready if there is room and data is not flowing out
  assign in_rsp_ready_o =
      in_rsp_valid_i && |is_id_rsvd;  // AXI 4 allows ready to depend on the valid signal
  assign rsv_ready_o = |(~ram_v);


  /////////////
  // Outputs //
  /////////////

  //  In this part, the output signals are declared and set.
  //
  //  Involved signals are:
  //    * cur_out_id_bin_d, cur_out_id_bin_q, cur_out_id_onehot: Stores which AXI identifier is
  //      currently at the output.
  //    * cur_out_valid_d, cur_out_valid_q: Expresses whether the output is valid.
  //    * cur_out_addr_onehot_d, cur_out_addr_onehot_q: Stores which RAM address is currently at the
  //      output.

  // Output identifier and address
  logic [IDWidth-1:0] cur_out_id_bin_d;
  logic [IDWidth-1:0] cur_out_id_bin_q;
  logic [NumIds-1:0] cur_out_id_onehot;
  logic cur_out_valid_d;
  logic cur_out_valid_q;

  logic [TotCapa-1:0] cur_out_addr_onehot_d;
  logic [TotCapa-1:0] cur_out_addr_onehot_q;

  // Output identifier from binary to one-hot
  for (genvar i_bit = 0; i_bit < NumIds; i_bit = i_bit + 1) begin : cur_out_bin_to_onehot
    assign cur_out_id_onehot[i_bit] = i_bit == cur_out_id_bin_q;
  end : cur_out_bin_to_onehot

  // Store the next address to be released
  for (genvar i_addr = 0; i_addr < TotCapa; i_addr = i_addr + 1) begin : gen_next_addr_out
    assign cur_out_addr_onehot_d[i_addr] = |nxt_addr_onehot_rot[i_addr];
  end : gen_next_addr_out

  // Transform next id to release to binary representation for more compact storage
  logic [IDWidth-1:0] nxt_id_to_release_bin;

  always_comb begin
    nxt_id_to_release_bin = '0;
    for (int unsigned i_id = 0; i_id < NumIds; i_id = i_id + 1) begin
      if (nxt_id_to_release_onehot[i_id]) begin
        nxt_id_to_release_bin = i_id[IDWidth - 1:0];
      end
    end
  end

  // Calculate the length of each AXI identifier queue after the potential output
  for (genvar i_id = 0; i_id < NumIds; i_id = i_id + 1) begin : gen_len_after_output
    assign rsp_len_after_out[i_id] = out_rsp_valid_o && out_rsp_ready_i &&
        cur_out_id_onehot[i_id] && tail_cnt_id[i_id] == 1 ? rsp_len_q[i_id] - 1 : rsp_len_q[i_id];
  end : gen_len_after_output

  // Recall if the current output is valid
  assign cur_out_valid_d = |nxt_id_to_release_onehot;

  assign cur_out_id_bin_d = nxt_id_to_release_bin;
  assign out_rsp_valid_o = |cur_out_valid_q;
  assign rsp_o.merged_payload.id = cur_out_id_bin_q;
  assign rsp_o.merged_payload.payload = pyld_ram_out_data;

  ////////////////
  // Handshakes //
  ////////////////

  //  In this part, four sub-parts are treated:
  //    * Output preparation: if the considered AXI identifier is the next AXI identifier to
  //      release, then assign the payload RAM output to the pre_tail or the tail pointer.
  //    * Input handshake: if the considered AXI identifier is the next AXI identifier to release,
  //      then: 
  //      - Update the linked list lengths.
  //      - Update the pointers, including corner cases.
  //      - Assign the payload RAM input address.
  //      - Assign the corresponding metadata RAM output address.
  //    * Reservation handshake: if the considered AXI identifier is the next AXI identifier to
  //      release, then:
  //      - Update the linked list lengths.
  //      - Update the pointers in some corner cases.
  //      - Assign both metadata RAMs input addresses.
  //    * Output handshake: if the considered AXI identifier is the next AXI identifier to release,
  //        then:
  //      - Update the linked list lengths.
  //      - Update the pointers, including corner cases.
  //      - Assign the corresponding metadata RAM output address.

  for (genvar i_id = 0; i_id < NumIds; i_id = i_id + 1) begin : id_isolated_comb

    always_comb begin
      // Default assignments
      rsp_len_d[i_id] = rsp_len_q[i_id];
      rsv_len_d[i_id] = rsv_len_q[i_id];
      is_rsp_head_emptybox_d[i_id] = is_rsp_head_emptybox_q[i_id];

      update_pt_from_ram_d[i_id] = 1'b0;
      update_rsp_from_ram_d[i_id] = 1'b0;
      update_rsv_heads[i_id] = 1'b0;
      update_t_from_pt[i_id] = 1'b0;

      pgbk_rsp_with_rsv[i_id] = 1'b0;
      pgbk_t_with_rsv[i_id] = 1'b0;
      pgbk_t_with_rsp_d[i_id] = 1'b0;
      pgbk_pt_with_rsv[i_id] = 1'b0;
      pgbk_pt_with_rsp_d[i_id] = 1'b0;

      pyld_ram_in_addr_id[i_id] = '0;
      pyld_ram_out_addr_id[i_id] = '0;
      pyld_ram_in_wmask_id[i_id] = '0;
      pyld_ram_out_wmask_id[i_id] = '0;
      meta_ram_in_addr_id[i_id] = '0;
      meta_ram_out_addr_tail_id[i_id] = '0;
      meta_ram_out_addr_rsp_head_id[i_id] = '0;

      meta_ram_in_content_id[i_id] = '0;

      // Output preparation
      if (nxt_id_to_release_onehot[i_id]) begin
        // The pre_tail points not to the current output to provide, but to the next. If we
        // currently provide output (handshake), make sure to be ready in the next cycle. The RAM
        // has a read latency of one clock cycle.
        if (out_rsp_valid_o && out_rsp_ready_i && cur_out_id_onehot[i_id]) begin
          if (tail_cnt_id[i_id] == 1) begin
            pyld_ram_out_addr_id[i_id] = pre_tails[i_id];
            // Set the corresponding payload RAM output wmask bit to one.
            for (int unsigned i_bur = 0; i_bur < MaxBurstLen; i_bur = i_bur + 1) begin
              pyld_ram_out_wmask_id[i_id][i_bur] = pre_tail_cnt_id[i_id] ==
                  MaxBurstLen[BurstLenWidth - 1:0] - i_bur[BurstLenWidth - 1:0];
            end
          end else begin
            pyld_ram_out_addr_id[i_id] = tails[i_id];
            // Set the corresponding payload RAM output wmask bit to one.
            for (int unsigned i_bur = 0; i_bur < MaxBurstLen; i_bur = i_bur + 1) begin
              pyld_ram_out_wmask_id[i_id][i_bur] = tail_cnt_id[i_id] ==
                  MaxBurstLen[BurstLenWidth - 1:0] - i_bur[BurstLenWidth - 1:0] + 1;
            end
          end
        end else begin
          pyld_ram_out_addr_id[i_id] = tails[i_id];
          // Set the corresponding payload RAM output wmask bit to one.
          for (int unsigned i_bur = 0; i_bur < MaxBurstLen; i_bur = i_bur + 1) begin
            pyld_ram_out_wmask_id[i_id][i_bur] =
                tail_cnt_id[i_id] == MaxBurstLen[BurstLenWidth - 1:0] - i_bur[BurstLenWidth - 1:0];
          end
        end
      end

      // Input handshake
      if (in_rsp_ready_o && in_rsp_valid_i && rsp_i.merged_payload.id == i_id) begin

        // If this is the last data of the burst, then update the pointers
        if (rsv_cnt_id[i_id] == 1) begin

          rsp_len_d[i_id] = rsp_len_d[i_id] + 1;

          // As the reservation length refers to the number of reserved cells that are not occupied,
          // it must be decremented on response input.
          rsv_len_d[i_id] = rsv_len_d[i_id] - 1;

          if (rsp_heads[i_id] != rsv_heads_q[i_id]) begin
            // If the reservation head is ahead of the response head, then the rsp_head can follow
            // the pointer from the metadata RAM.
            update_rsp_from_ram_d[i_id] = 1'b1;
          end else begin
            // Else, rsp_head needs to be updated by piggybacking with rsv_head, as this is the only
            // way to satisfy the placement condition for the response head: (a) the response head
            // must be either on the next reserved cell ready to take a response, or (b) if there is
            // no such cell, then it should be equal to the rsp_head. Therefore, here, if the
            // reservation head gets updated in the current clock cycle, then the response head
            // follows it and (a) is respected. Else, both pointers keep their (equal) position and
            // (b) is respected. Note that in the latter case, the linked list for this AXI
            // identifier is now full and will not take any new response before a new reservation
            // has been performed.
            pgbk_rsp_with_rsv[i_id] = 1'b1;
          end

          // Pull the pre_tail with the response head in the case where the pre-tail could not be
          // placed on the second-to-last occupied address of the queue because there was at most
          // one response element in the queue.
          if (pre_tails[i_id] == rsp_heads[i_id] && (
              rsp_len_after_out[i_id] == 0 || (
                  rsp_len_after_out[i_id] == 1 && tails[i_id] == pre_tails[i_id]))) begin
            pgbk_pt_with_rsp_d[i_id] = 1'b1;
          end
        end

        // Store the data
        pyld_ram_in_addr_id[i_id] = rsp_heads[i_id];

        // Update the response head pointer position
        meta_ram_out_addr_rsp_head_id[i_id] = rsp_heads[i_id];

        // Set the payload RAM input wmask
        for (int unsigned i_bur = 0; i_bur < MaxBurstLen; i_bur = i_bur + 1) begin
          pyld_ram_in_wmask_id[i_id][i_bur] = rsp_cnt_id[i_id] == i_bur[BurstLenWidth - 1:0];
        end
      end

      // Reservation handshake
      if (rsv_valid_i && rsv_ready_o && rsv_req_id_onehot_i[i_id]) begin

        rsv_len_d[i_id] = rsv_len_d[i_id] + 1;
        update_rsv_heads[i_id] = 1'b1;

        // If the queue is already initiated, then update the head position in the RAM.
        if (|rsv_len_q[i_id] || |rsp_len_after_out[i_id]) begin
          meta_ram_in_addr_id[i_id] = rsv_heads_q[i_id];
          meta_ram_in_content_id[i_id].nxt_elem = nxt_free_addr;

          if (rsv_heads_q[i_id] == rsp_heads[i_id]) begin
            if (rsv_len_q[i_id] == 0) begin
              // The rsp_head is placed on a reserved RAM address, but it could not yet be updated
              // to the next reserved address in the linked list, as this next address has not yet
              // been reserved. In case rsv_head is updated, make sure to also update rsp_head
              // (piggybacking) to have rsp_head pointing to next free reserved address.
              pgbk_rsp_with_rsv[i_id] = 1'b1;
              is_rsp_head_emptybox_d[i_id] = 1'b1;

              // Also update pre_tail with rsv_head, it was blocked behind rsp_head. Note that
              // rsp_len_after_out != 0, hence rsv_len_q == 0. Further we have rsv_heads_q ==
              // rsp_heads.  
              if (rsp_len_after_out[i_id] == 1) begin
                pgbk_pt_with_rsv[i_id] = 1'b1;
              end
            end
          end
        end else begin
          // Else, piggyback everything as a new queue is created from scratch.
          pgbk_rsp_with_rsv[i_id] = 1'b1;
          pgbk_t_with_rsv[i_id] = 1'b1;
          pgbk_pt_with_rsv[i_id] = 1'b1;
          is_rsp_head_emptybox_d[i_id] = 1'b1;
        end
      end

      // Output handshake
      if (out_rsp_valid_o && out_rsp_ready_i && cur_out_id_onehot[i_id]) begin

        // If this is the last response in the burst, then update the pointers.
        if (tail_cnt_id[i_id] == 1) begin

          rsp_len_d[i_id] = rsp_len_d[i_id] - 1;
          // Update the tail to take the current value of the pre_tail.
          update_t_from_pt[i_id] = 1'b1;

          if (rsp_heads[i_id] != pre_tails[i_id]) begin
            // If the response head is not at the same address as the pre_tail, then the pre_tail
            //  can be safely updated from the RAM without risking to overtake the response pointer.
            update_pt_from_ram_d[i_id] = 1'b1;
            meta_ram_out_addr_tail_id[i_id] = pre_tails[i_id];
          end else begin
            // If the pre_tail points to the same value as the rsp_head, then to respect the pointer
            // ordering (precisely here, pre_tail <= rsp_head in the order defined by the linked
            // list), the pre_tail must be updated only if the response head is updated
            // (piggybacking). This also covers the case  "pre_tail == rsp_head == rsv_head AND
            // current reservation handshake is taking place".
            pgbk_pt_with_rsp_d[i_id] = 1'b1;
          end
        end
      end
    end
  end

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      rsp_heads_q <= '{default: '0};
      rsv_heads_q <= '{default: '0};
      tails_q <= '{default: '0};
      pre_tails_q <= '{default: '0};
      rsp_len_q <= '{default: '0};
      rsv_len_q <= '{default: '0};

      rsv_cnt_q <= '{default: '0};
      rsp_cnt_q <= '{default: '0};

      update_pt_from_ram_q <= '{default: '0};
      update_rsp_from_ram_q <= '{default: '0};
      pyld_ram_out_wmask_q <= '{default: '0};

      is_rsp_head_emptybox_q <= '{default: '1};
      pgbk_t_with_rsp_q <= '{default: '0};
      pgbk_pt_with_rsp_q <= '{default: '0};
    end else begin
      rsp_heads_q <= rsp_heads_d;
      rsv_heads_q <= rsv_heads_d;
      tails_q <= tails_d;
      pre_tails_q <= pre_tails_d;
      rsp_len_q <= rsp_len_d;
      rsv_len_q <= rsv_len_d;

      rsv_cnt_q <= rsv_cnt_d;
      rsp_cnt_q <= rsp_cnt_d;

      update_pt_from_ram_q <= update_pt_from_ram_d;
      update_rsp_from_ram_q <= update_rsp_from_ram_d;
      pyld_ram_out_wmask_q <= pyld_ram_out_wmask_d;

      is_rsp_head_emptybox_q <= is_rsp_head_emptybox_d;
      pgbk_t_with_rsp_q <= pgbk_t_with_rsp_d;
      pgbk_pt_with_rsp_q <= pgbk_pt_with_rsp_d;
    end
  end

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      cur_out_valid_q <= '0;
      cur_out_id_bin_q <= '0;
      cur_out_addr_onehot_q <= '0;
    end else begin
      cur_out_valid_q <= cur_out_valid_d;
      cur_out_id_bin_q <= cur_out_id_bin_d;
      cur_out_addr_onehot_q <= cur_out_addr_onehot_d;
    end
  end

  // Payload RAM instance
  prim_generic_ram_2p #(
    .Width(PayloadRamWidth),
    .DataBitsPerMask(PayloadWidth),
    .Depth(TotCapa)
  ) i_payload_ram (
    .clk_a_i     (clk_i),
    .clk_b_i     (clk_i),

    .a_req_i     (pyld_ram_in_req),
    .a_write_i   (pyld_ram_in_write),
    .a_wmask_i   (pyld_ram_in_wmask_expanded),
    .a_addr_i    (pyld_ram_in_addr),
    .a_wdata_i   (pyld_ram_in_burst_data),
    .a_rdata_o   (),

    .b_req_i     (pyld_ram_out_req),
    .b_write_i   (pyld_ram_out_write),
    .b_wmask_i   (pyld_ram_out_wmask_expanded),
    .b_addr_i    (pyld_ram_out_addr),
    .b_wdata_i   (),
    .b_rdata_o   (pyld_ram_out_burst_data)
  );

  // Metadata RAM instance
  prim_generic_ram_2p #(
    .Width(BankAddrWidth),
    .DataBitsPerMask(1),
    .Depth(TotCapa)
  ) i_meta_ram_out_tail (
    .clk_a_i     (clk_i),
    .clk_b_i     (clk_i),

    .a_req_i     (meta_ram_in_req),
    .a_write_i   (meta_ram_in_write),
    .a_wmask_i   (meta_ram_in_wmask),
    .a_addr_i    (meta_ram_in_addr),
    .a_wdata_i   (meta_ram_in_content),
    .a_rdata_o   (),

    .b_req_i     (meta_ram_out_req),
    .b_write_i   (meta_ram_out_write),
    .b_wmask_i   (meta_ram_out_wmask),
    .b_addr_i    (meta_ram_out_addr_tail),
    .b_wdata_i   (),
    .b_rdata_o   (meta_ram_out_rsp_tail)
  );

  // Metadata RAM instance
  prim_generic_ram_2p #(
    .Width(BankAddrWidth),
    .DataBitsPerMask(1),
    .Depth(TotCapa)
  ) i_meta_ram_out_rsp_head (
    .clk_a_i     (clk_i),
    .clk_b_i     (clk_i),

    .a_req_i     (meta_ram_in_req),
    .a_write_i   (meta_ram_in_write),
    .a_wmask_i   (meta_ram_in_wmask),
    .a_addr_i    (meta_ram_in_addr),
    .a_wdata_i   (meta_ram_in_content),
    .a_rdata_o   (),

    .b_req_i     (meta_ram_out_req),
    .b_write_i   (meta_ram_out_write),
    .b_wmask_i   (meta_ram_out_wmask),
    .b_addr_i    (meta_ram_out_addr_rsp_head),
    .b_wdata_i   (),
    .b_rdata_o   (meta_ram_out_rsp_head)
  );

endmodule
