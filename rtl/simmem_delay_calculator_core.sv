// Copyright lowRISC contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

// The delay calculator core is responsible for snooping the traffic from the requester with the
// help of its delay calculator wrapper and deducing the enable signals for the message banks.
// Wrapped in the delay calculator module, it can assume that no write data request arrives before
// the corresponding write address request.
//
// Overview: The pendin requests are stored in arrays of slots (one array of wslt_t for write
// requests and one array of rslt_t for read requests). For burst support, each slot supports status
// information for each of the single corresponding requests:
//  * data_v: 1'b0 iff the corresponding request has not arrived yet.
//  * mem_pending: 1'b1 if the request has been submitted to the corresponding rank, which has not
//    responded yet.
//  * mem_done: 1'b0 iff the request has not been completed yet. A request identifier that exceeds
//    the burst length of the current slot's burst has its mem_done bit immediately set to 1'b1.
//
// Write slot management:
// * When a write address request is accepted, along with a certain "immediate" number
//   wdata_immediate_cnt_i of write data requests, it occupies the lowest-identifier available write
//   slot. The wdata_immediate_cnt_i first bits of the data_v signal are set to one to indicate that
//   the slots are occupied. As they are to be treated, the corresponding bits of mem_pending and
//   mem_done are set to 0. The next burst_len-wdata_immediate_cnt_i bits, corresponding to the
//   still awaited write data requests, are set to zero in the three signals. The rest of the bits,
//   corresponding to data beyond the burst length, are set to (data_v, mem_pending,
//   mem_done)=(1,0,1).
// * Each slot exposes, per rank, one optimal (as defined by the scheduling strategy) data request,
//   along with the corresponding cost. If there is at least one such candidate data request, then
//   the signal opti_w_valid_per_slot is set to one. Else, it is set to zero.
// * When a data request is the optimal among all across all slots, and if the corresponding rank is
//   ready to take a request, then its mem_pending signal is set to one. When the request treatment
//   simulated duration is completed, its mem_pending bit is reset to zero and its mem_done bit is
//   set to one.
// * When the data_v array of a given slot is complete with ones (actually, some cycles before), the
//   write message bank is allowed to release the corresponding response.
//
// Difference between read and write transactions:
// * There are no separate read data requests. Therefore, the read slots do not have data_v bit
//   arrays.
// * There is one response per read data, as opposed to only one per write slot. Therefore, the read
//   output has counters to hold the number of burst data to be released. Also, the counter is
//   notified everytime a read data completes.
// * As all read data arrives at the same time, they don't require individual ages.
//
// Scheduling strategy: The implemented strategy is aggressive FR-FCFS (first-ready
// first-come-first-served). Priorities are given in the decreasing order:
// * The request and the corresponding rank must be ready.
// * The response time of the response bank must be minimal.
// * Older requests are treated first.
//
// Age management for requests: Age is treated in a relative manner using a binary age matrix. Only
// the exclisive top-right area (i.e., (Aij) for i<j) is considered, to minimize the overhead of the
// circuit. For i<j, the entry indexed by j is older than i iff Aij=1'b1. Age is tracked:
// * For each individual write data request.
// * For each write address request (i.e., one age entry for each write slot).
// * For each read address request (i.e., one age entry for each read slot).
//
// Two distinct age matrices: As write address requests ages are never compared to something else
// than another write address request (or equivalently, write slot age), those are held in a
// separate, smaller age matrix.
//
// Request cost: Three costs (measured in clock cycles) are supported by the delay calculator:
// * Cost of row hit (RowHitCost): if the requested row was in the row buffer.
// * Cost of activation + row hit (RowHitCost + ActivationCost): if no row was in the row buffer.
// * Cost of precharge + activation + row hit (RowHitCost + ActivationCost + PrechargeCost): if the
//   another row was in the row buffer. DRAM refreshing is not simulated.
//
// Cost categorization: As the entropy of the cost values is very low (takes only 3 values), they
// are categorized on 2 bits to ease comparisons.
//
// Interleaving is not supported yet, but the basic structure to integrate interleaving is present:
// candidate requests are split per rank. Additionally, relevant blocks are surrounded by `for
// (genvar i_rk...` loops.
//

module simmem_delay_calculator_core #(
    // NumRanks must be a power of two, used for address interleaving.
    parameter int unsigned NumRanks = 1,  // Interleaving is not supported yet.

    localparam
        int unsigned NumRksW = NumRanks == 1 ? 1 : $clog2 (NumRanks)  // derived parameter
) (
    input logic clk_i,
    input logic rst_ni,

    // Write address request from the requester.
    input simmem_pkg::waddr_t                                         waddr_i,
    // Internal identifier corresponding to the write address request (issued by the write response
    // bank).
    input simmem_pkg::write_iid_t                                     waddr_iid_i,
    // Number of write data packets that come with the write address (which were buffered buffered
    // by the wrapper, plus potentially one coming concurrently).
    input logic                   [simmem_pkg::MaxBurstLenField-1:0] wdata_immediate_cnt_i,

    // Write address request valid from the requester.
    input  logic waddr_valid_i,
    // Blocks the write address request if there is no slot in the delay calculator to treat it.
    output logic waddr_ready_o,

    // Write address request valid from the requester.
    input logic wdata_valid_i,

    // Write address request from the requester.
    input simmem_pkg::raddr_t    raddr_i,
    // Internal identifier corresponding to the read address request (issued by the read response
    // bank).
    input simmem_pkg::read_iid_t raddr_iid_i,

    // Read address request valid from the requester.
    input  logic raddr_valid_i,
    // Blocks the read address request if there is no read slot in the delay calculator to treat it.
    output logic raddr_ready_o,

    // Release enable output signals and released address feedback.
    output logic [simmem_pkg::WRspBankCapa-1:0] wrsp_release_en_mhot_o,
    output logic [ simmem_pkg::RDataBankCapa-1:0] rdata_release_en_mhot_o,

    // Release confirmations sent by the message banks
    input logic [simmem_pkg::WRspBankCapa-1:0] wrsp_released_iid_onehot_i,
    input logic [ simmem_pkg::RDataBankCapa-1:0] rdata_released_iid_onehot_i,

    // Ready signals from the response banks
    input logic wrsp_bank_ready_i,
    input logic rrsp_bank_ready_i,

    // Ready signals for the response banks
    output logic wrsp_bank_ready_o,
    output logic rrsp_bank_ready_o
);

  import simmem_pkg::*;

  /////////////////////////////////
  // Request cost categorization //
  /////////////////////////////////

  // Categorizes the actual cost to have comparisons on fewer bits. Therefore, the ordering of the
  // values in the enumeration is important.
  typedef enum logic [1:0] {
    C_CAS = 0,
    C_ACT_CAS = 1,
    C_PRECH_ACT_CAS = 2,
    COST_NO_CANDIDATE = 3
  // COST_NO_CANDIDATE is a special state: if the optimal cost for all the candidates for a rank is
  // COST_NO_CANDIDATE, then it means that the set of candidates for this rank is the empty set.
  } mem_cost_category_e;
  // The NumCostCats constant determines how many disjoint reductions will be needed: for each
  // (rank, category) pair, an optimal entry is calculated. Therefore, it does not count the
  // COST_NO_CANDIDATE category.
  localparam int unsigned NumCostCats = 3;
  localparam int unsigned NumCostCatsW = $clog2(NumCostCats);

  /**
  * Determines and compresses the cost of a request, depending on the requested address and the
  * current status of the corresponding rank.
  *
  * @param address the requested address.
  * @param is_row_open 1'b1 iff a row is currently open in the corresponding rank.
  * @param open_row_buf_ident the start address of the open row, if applicable.
  * @return the cost of the access, in clock cycles.
  */
  function automatic mem_cost_category_e det_cost_cat(
      logic [GlobalMemCapaW-1:0] address, logic is_row_open,
      logic [RowIdWidth-1:0] open_row_buf_ident);
    if (is_row_open && address[GlobalMemCapaW-1:RowBufLenW] ==
        open_row_buf_ident) begin
      return C_CAS;
    end else if (!is_row_open) begin
      return C_ACT_CAS;
    end else begin
      return C_PRECH_ACT_CAS;
    end
  endfunction : det_cost_cat

  /**
  * Decategorizes a request cost to retrieve the actual value from its category.
  *
  * @param cost_category the categorized cost.
  * @return the actual cost corresponding to this categorized cost.
  */
  function automatic logic [DelayW-1:0] decategorize_mem_cost(
      mem_cost_category_e cost_category);
    case (cost_category)
      C_CAS: begin
        return DelayW'(RowHitCost);
      end
      C_ACT_CAS: begin
        return DelayW'(RowHitCost + ActivationCost);
      end
      C_PRECH_ACT_CAS: begin
        return DelayW'(RowHitCost + ActivationCost + PrechargeCost);
      end
      default: begin  // COST_NO_CANDIDATE
        // If there is no candidate request for a given rank, then the corresponding counter remains
        // 0.
        return 0;
      end
    endcase
  endfunction : decategorize_mem_cost

  /////////////////////
  // Rank assignment //
  /////////////////////

  /**
  * Determines to which rank a given address is assigned. It uses the least significant bits for
  * interleaving.
  *
  * @param address the input address.
  * @return the rank index to which the address is assigned.
  */
  function automatic logic [NumRksW-1:0] get_assigned_rk_id(
      logic [GlobalMemCapaW-1:0] address);
    if (NumRanks == 1) begin
      return 0;
    end
    return address[NumRksW - 1:0];
  endfunction : get_assigned_rk_id

  ///////////////////////////////////////////
  // Slot constants, types and declaration //
  ///////////////////////////////////////////

  // As their shape and treatment is different, slots for read and write bursts are disjoint: there
  // is one array of slots for read bursts, and one array for write bursts.

  // Maximal number of write data entries: at most MaxBurstEffLen per slot.
  localparam MaxNumWEntries = NumWSlots * MaxBurstEffLen;
  // Maximal number of read data entries: at most MaxBurstEffLen per slot.
  localparam MaxNumREntries = NumRSlots * MaxBurstEffLen;

  // Slot type definition
  typedef struct packed {
    logic [MaxBurstEffLen-1:0] mem_done;
    logic [MaxBurstEffLen-1:0] mem_pending;
    logic [MaxBurstEffLen-1:0] data_v;  // Data valid
    logic burst_fixed;
    logic [AxSizeWidth-1:0] burst_size;
    logic [AxAddrWidth-1:0] addr;
    write_iid_t iid;  // Internal identifier (address in the response bank's RAM)
    logic v;  // Valid bit
  } wslt_t;

  typedef struct packed {
    logic [MaxBurstEffLen-1:0] mem_done;
    logic [MaxBurstEffLen-1:0] mem_pending;
    logic burst_fixed;
    logic [AxSizeWidth-1:0] burst_size;
    logic [AxAddrWidth-1:0] addr;
    read_iid_t iid;  // Internal identifier (address in the response bank's RAM)
    logic v;  // Valid bit
  } rslt_t;

  // Slot declarations
  wslt_t wslt_d[NumWSlots];
  wslt_t wslt_q[NumWSlots];
  rslt_t rslt_d[NumRSlots];
  rslt_t rslt_q[NumRSlots];

  // Candidate signals calculation: is a write data request candidate for a given (rank, category)
  // pair.
  logic [MaxBurstEffLen-1:0] is_wd_cand_cat_mhot[NumRanks][NumCostCats][NumWSlots];
  // Is a read data request candidate for a given (rank, category) pair.
  logic [MaxBurstEffLen-1:0] is_rdata_cand_cat_mhot[NumRanks][NumCostCats][NumRSlots];

  for (genvar i_rk = 0; i_rk < NumRanks; i_rk = i_rk + 1) begin : candidates_outer
    for (genvar i_cat = 0; i_cat < NumCostCats; i_cat = i_cat + 1) begin : candidates_cat
      for (genvar i_slt = 0; i_slt < NumWSlots; i_slt = i_slt + 1) begin : candidates_w_inner
        for (genvar i_bit = 0; i_bit < MaxBurstEffLen; i_bit = i_bit + 1) begin : candidates_w_bit
          // A wslot entry is candidate for a (rank, cat) pair if it the slot is valid
          assign is_wd_cand_cat_mhot[i_rk][i_cat][i_slt][i_bit] = wslt_q[i_slt].v
              // And the entry is valid and has no memory operation pending
              & wslt_q[i_slt].data_v[i_bit] & ~wslt_q[i_slt].mem_pending[i_bit] &
              // And the memory operation has not been performed yet
              ~wslt_q[i_slt].mem_done[i_bit] &
              // And the address corresponds to the right rank
              NumRksW'(i_rk) == get_assigned_rk_id(slt_waddrs[i_slt][i_bit]) &
              // And the address yields the right cost.
              det_cost_cat(slt_waddrs[i_slt][i_bit], is_row_open_q[i_rk], row_buf_ident_q[i_rk])
              == NumCostCatsW'(i_cat);
        end : candidates_w_bit
      end : candidates_w_inner
      for (genvar i_slt = 0; i_slt < NumRSlots; i_slt = i_slt + 1) begin : candidates_r_inner
        for (genvar i_bit = 0; i_bit < MaxBurstEffLen; i_bit = i_bit + 1) begin : candidates_r_bit
          // Identical to wslot entries, with the exception that data_v signals are absent in read
          // slots and replaced by the slot .v signal.
          assign is_rdata_cand_cat_mhot[i_rk][i_cat][i_slt][i_bit] = rslt_q[i_slt].v &
          ~rslt_q[i_slt].mem_pending[i_bit] & ~rslt_q[i_slt].mem_done[i_bit] &
          NumRksW'(i_rk) == get_assigned_rk_id(slt_raddrs[i_slt][i_bit]) &
          det_cost_cat(slt_raddrs[i_slt][i_bit], is_row_open_q[i_rk], row_buf_ident_q[i_rk]) ==
          NumCostCatsW'(i_cat);
        end : candidates_r_bit
      end : candidates_r_inner
    end : candidates_cat
  end : candidates_outer

  // Determine the next candidate read data per slot
  logic [MaxBurstEffLen-1:0] slt_nxt_data_cat_onehot[NumRanks][NumCostCats][NumRSlots];
  logic [MaxBurstEffLen-1:0] slt_nxt_data_onehot[NumRanks][NumRSlots];

  for (genvar i_rk = 0; i_rk < NumRanks; i_rk = i_rk + 1) begin : det_rdata_outer
    for (genvar i_cat = 0; i_cat < NumCostCats; i_cat = i_cat + 1) begin : det_rdata_cat
      for (genvar i_slt = 0; i_slt < NumRSlots; i_slt = i_slt + 1) begin : det_rdata
        assign slt_nxt_data_cat_onehot[i_rk][i_cat][i_slt][0] =
            is_rdata_cand_cat_mhot[i_rk][i_cat][i_slt][0];
        for (genvar i_bit = 1; i_bit < MaxBurstEffLen; i_bit = i_bit + 1) begin : det_rdata_inner
          assign slt_nxt_data_cat_onehot[i_rk][i_cat][i_slt][i_bit] =
              is_rdata_cand_cat_mhot[i_rk][i_cat][i_slt][i_bit] &
              ~|is_rdata_cand_cat_mhot[i_rk][i_cat][i_slt][i_bit-1:0];
        end : det_rdata_inner
      end : det_rdata
    end : det_rdata_cat

    // Find the lowest cost read entry per rank and per slot
    for (genvar i_slt = 0; i_slt < NumRSlots; i_slt = i_slt + 1) begin : det_rdata_reduce
      always_comb begin
        if (|slt_nxt_data_cat_onehot[i_rk][C_CAS][i_slt]) begin
          slt_nxt_data_onehot[i_rk][i_slt] = slt_nxt_data_cat_onehot[i_rk][C_CAS][i_slt];
        end else if (|slt_nxt_data_cat_onehot[i_rk][C_ACT_CAS][i_slt]) begin
          slt_nxt_data_onehot[i_rk][i_slt] = slt_nxt_data_cat_onehot[i_rk][C_ACT_CAS][i_slt];
        end else begin
          slt_nxt_data_onehot[i_rk][i_slt] = slt_nxt_data_cat_onehot[i_rk][C_PRECH_ACT_CAS][i_slt];
        end
      end
    end : det_rdata_reduce
  end : det_rdata_outer

  //////////////////////////////////
  // Determine the next free slot //
  //////////////////////////////////

  // In this part, the free slot with lowest position in the slots array is determined for both read
  // and write bursts.

  // Intermediate multi-hot signals determining which slots are free.
  logic [NumWSlots-1:0] free_wslt_mhot;
  logic [NumRSlots-1:0] free_rslt_mhot;
  // Intermediate one-hot signals determining the position of the free slot with lowest position in
  // the slots arrays.
  logic [NumWSlots-1:0] nxt_free_wslt_onehot;
  logic [NumRSlots-1:0] nxt_free_rslt_onehot;

  // Determine the next free slot for write slots.
  for (genvar i_slt = 0; i_slt < NumWSlots; i_slt = i_slt + 1) begin : gen_nxt_free_w_slot
    assign free_wslt_mhot[i_slt] = ~wslt_q[i_slt].v;
    if (i_slt == 0) begin
      assign nxt_free_wslt_onehot[0] = free_wslt_mhot[0];
    end else begin
      assign nxt_free_wslt_onehot[i_slt] = free_wslt_mhot[i_slt] && ~|free_wslt_mhot[i_slt - 1:0];
    end
  end : gen_nxt_free_w_slot

  // Determine the next free slot for read slots.
  for (genvar i_slt = 0; i_slt < NumRSlots; i_slt = i_slt + 1) begin : gen_nxt_free_r_slot
    assign free_rslt_mhot[i_slt] = ~rslt_q[i_slt].v;
    if (i_slt == 0) begin
      assign nxt_free_rslt_onehot[0] = free_rslt_mhot[0];
    end else begin
      assign nxt_free_rslt_onehot[i_slt] = free_rslt_mhot[i_slt] && ~|free_rslt_mhot[i_slt - 1:0];
    end
  end : gen_nxt_free_r_slot

  // The module is ready to accept address requests if there is a free corresponding (write or read)
  // slot.
  assign wrsp_bank_ready_o = |nxt_free_wslt_onehot;
  assign rrsp_bank_ready_o = |nxt_free_rslt_onehot;

  assign waddr_ready_o = wrsp_bank_ready_o & wrsp_bank_ready_i;
  assign raddr_ready_o = rrsp_bank_ready_o & rrsp_bank_ready_i;

  ////////////////////////////////////////////////////////////
  // Age matrix constants, declaration and helper functions //
  ////////////////////////////////////////////////////////////

  // An age matrix cell is set at (i=lower, j=higher) iff j is older than i (if both entries/slots
  // are valid, else the cell value is irrelevant).
  //
  // The age matrices are indexed as the following example, for 3 write slots (W), 5 read slots (R)
  // and a maximal write burst length of 2 write data (D) per write address (the x symbols represent
  // boolean values asserting "row is older than column").
  //
  // Main age matrix (main_age_matrix_d/main_age_matrix_q):
  //
  // *   D D D D D D R R R R R
  // *
  // * D   x x x x x x x x x x
  // * D     x x x x x x x x x
  // * D       x x x x x x x x
  // * D         x x x x x x x
  // * D           x x x x x x
  // * D             x x x x x
  // * R               x x x x
  // * R                 x x x
  // * R                   x x
  // * R                     x
  // * R
  //
  // Write slot age matrix (wslt_main_age_matrix_d/wslt_main_age_matrix_q):
  //
  // *   W W W
  // *
  // * W   x x
  // * W     x
  // * W
  //
  // Only the area marked by 'x' symbols is actually stored.
  //
  // Age matrix splitting: The main age matrix cannot be split in several disjoint sub-matrices to
  //  take advantage of the partition to different ranks, because this partition is made dynamically
  //  and changes during runtime, depending on the LSBs of entries' addresses.
  //
  // Auxiliary signal:
  //  * {main|wslt}_new_entry: Indicates whether an entry of the matrix has just been added as a
  //    candidate for a memory request.

  // Main age matrix
  localparam MAgeMRSltStart = MaxNumWEntries;

  localparam MainAgeMatrixSide = MaxNumWEntries + NumRSlots;
  localparam MainAgeMatrixSideWidth = $clog2(MainAgeMatrixSide);

  // Age matrix instantiations
  logic [MainAgeMatrixSide-1:0] main_age_matrix[MainAgeMatrixSide-1:0];
  logic [NumWSlots-1:0] wslt_age_matrix[NumWSlots-1:0];

  // Auxiliary signals
  logic main_new_entry[MainAgeMatrixSide];
  logic wslt_new_entry[NumWSlots];

  // Main age matrix management
  for (genvar i = 0; i < MainAgeMatrixSide; i = i + 1) begin : gen_main_matrix_outer
    for (genvar j = 0; j < MainAgeMatrixSide; j = j + 1) begin : gen_main_matrix_inner
      if (i < j) begin : gen_main_matrix_flop
        logic matrix_elem_q, matrix_elem_d;
        always @(posedge clk_i or negedge rst_ni) begin
          if (~rst_ni) begin
            matrix_elem_q <= 0;
          end else begin
            matrix_elem_q <= matrix_elem_d;
          end
        end
        // Matrix_elem_q is set when j is older than i
        always_comb begin
          matrix_elem_d = matrix_elem_q;
          if (main_new_entry[i]) begin
            matrix_elem_d = 1'b1;
          end else if (main_new_entry[j]) begin
            matrix_elem_d = 1'b0;
          end
        end
        assign main_age_matrix[i][j] = matrix_elem_q;
      end else if (i == j) begin : g_matrix_diagonal
        // Diagonal always 0
        assign main_age_matrix[i][j] = 1'b0;
      end else begin
        // Mirror & invert matrix over diagonal
        assign main_age_matrix[i][j] = ~main_age_matrix[j][i];
      end
    end
  end

  // Write slot matrix management
  for (genvar i = 0; i < NumWSlots; i = i + 1) begin : gen_wslt_matrix_outer
    for (genvar j = 0; j < NumWSlots; j = j + 1) begin : gen_wslt_matrix_inner
      if (i < j) begin : gen_wslt_matrix_flop
        logic matrix_elem_q, matrix_elem_d;
        always @(posedge clk_i or negedge rst_ni) begin
          if (~rst_ni) begin
            matrix_elem_q <= 0;
          end else begin
            matrix_elem_q <= matrix_elem_d;
          end
        end
        // Matrix_elem_q is set when j is older than i
        always_comb begin
          matrix_elem_d = matrix_elem_q;
          if (wslt_new_entry[i]) begin
            matrix_elem_d = 1'b1;
          end else if (wslt_new_entry[j]) begin
            matrix_elem_d = 1'b0;
          end
        end
        assign wslt_age_matrix[i][j] = matrix_elem_q;
      end else if (i == j) begin : g_matrix_diagonal
        // Diagonal always 0
        assign wslt_age_matrix[i][j] = 1'b0;
      end else begin
        // Mirror & invert matrix over diagonal
        assign wslt_age_matrix[i][j] = ~wslt_age_matrix[j][i];
      end
    end
  end

  // Conditions used for masking in main age matrix reductions
  logic [MainAgeMatrixSide-1:0] matches_cond[NumRanks][NumCostCats];

  // Intermediate signal to determine whether an age matrix entry matches the conditions.
  logic [MaxBurstEffLen-1:0] slt_rd_matches_cond[NumRanks][NumCostCats][NumRSlots];

  // An entry matches the conditions, for a given (rank, cost category) pair, if all of the
  // following conditions are verified:
  //  * Its current cost category corresponds to the given cost category.
  //  * It is a candidate entry for the given rank (i.e., data_v bit set, mem_pending and mem_done
  //    unset, and the entry corresponding address maps to the given rank).
  for (genvar i_rk = 0; i_rk < NumRanks; i_rk = i_rk + 1) begin : cond_check_rnk
    for (genvar i_cat = 0; i_cat < NumCostCats; i_cat = i_cat + 1) begin : cond_check_cat
      // Check conditions for write data entries
      for (genvar i_slt = 0; i_slt < NumWSlots; i_slt = i_slt + 1) begin : cond_check_wslt
        for (genvar i_bit = 0; i_bit < MaxBurstEffLen; i_bit = i_bit + 1) begin : cond_check_wd
          assign matches_cond[i_rk][i_cat][i_slt*MaxBurstEffLen + i_bit] =
              is_wd_cand_cat_mhot[i_rk][i_cat][i_slt][i_bit];
        end : cond_check_wd
      end : cond_check_wslt
      // Check conditions for read data entries
      for (genvar i_slt = 0; i_slt < NumRSlots; i_slt = i_slt + 1) begin : cond_check_rslt
        for (genvar i_bit = 0; i_bit < MaxBurstEffLen; i_bit = i_bit + 1) begin : cond_check_rslt_bit
          assign slt_rd_matches_cond[i_rk][i_cat][i_slt][i_bit] =
              is_rdata_cand_cat_mhot[i_rk][i_cat][i_slt][i_bit];
        end : cond_check_rslt_bit
        assign matches_cond[i_rk][i_cat][MAgeMRSltStart + i_slt] =
            |slt_rd_matches_cond[i_rk][i_cat][i_slt];
      end : cond_check_rslt
    end : cond_check_cat
  end : cond_check_rnk

  // The reduction is done per rank One-hot signal
  logic [MainAgeMatrixSide-1:0] oldest_entry_of_category[NumRanks][NumCostCats];
  logic [MainAgeMatrixSide-1:0] opti_entry_onehot[NumRanks];
  mem_cost_category_e opti_cost_cat[NumRanks];

  // Matrix reduction
  for (genvar i_rk = 0; i_rk < NumRanks; i_rk = i_rk + 1) begin : reduce_rnk
    for (genvar i_cat = 0; i_cat < NumCostCats; i_cat = i_cat + 1) begin : reduce_cat
      for (genvar i = 0; i < MainAgeMatrixSide; i = i + 1) begin : reduce_age_per_category
        assign oldest_entry_of_category[i_rk][i_cat][i] = matches_cond[i_rk][i_cat][i] &
        ~|(main_age_matrix[i] & matches_cond[i_rk][i_cat]);
      end
    end

    // if/else_if sequence Reduce among categories: take the lowest cost category
    always_comb begin
      if (|oldest_entry_of_category[i_rk][C_CAS]) begin
        opti_cost_cat[i_rk] = C_CAS;
      end else if (|oldest_entry_of_category[i_rk][C_ACT_CAS]) begin
        opti_cost_cat[i_rk] = C_ACT_CAS;
      end else if (|oldest_entry_of_category[i_rk][C_PRECH_ACT_CAS]) begin
        opti_cost_cat[i_rk] = C_PRECH_ACT_CAS;
      end else begin
        opti_cost_cat[i_rk] = COST_NO_CANDIDATE;
      end
    end

    // Equivalently to the always_comb statement above: assign opti_cost_cat[i_rk] =
    // ({NumCostCatsW{|oldest_entry_of_category[i_rk][C_CAS]}} & C_CAS) |
    // ({NumCostCatsW{~|oldest_entry_of_category[i_rk][C_CAS] &
    // |oldest_entry_of_category[i_rk][C_ACT_CAS]}} & C_ACT_CAS) |
    // ({NumCostCatsW{~|oldest_entry_of_category[i_rk][C_CAS] &
    // ~|oldest_entry_of_category[i_rk][C_ACT_CAS] &
    // |oldest_entry_of_category[i_rk][C_PRECH_ACT_CAS]}} & C_PRECH_ACT_CAS) |
    // ({NumCostCatsW{~|oldest_entry_of_category[i_rk][C_CAS] &
    // ~|oldest_entry_of_category[i_rk][C_ACT_CAS] &
    // ~|oldest_entry_of_category[i_rk][C_PRECH_ACT_CAS]}} & COST_NO_CANDIDATE);

    // Using masks, find the optimal entry and its cost category
    assign opti_entry_onehot[i_rk] = oldest_entry_of_category[i_rk][C_CAS] |
        (oldest_entry_of_category[i_rk][C_ACT_CAS] &
        {MainAgeMatrixSide{~|oldest_entry_of_category[i_rk][C_CAS]}}) |
        (oldest_entry_of_category[i_rk][C_PRECH_ACT_CAS] &
        {MainAgeMatrixSide{~|oldest_entry_of_category[i_rk][C_CAS]}} &
        {MainAgeMatrixSide{~|oldest_entry_of_category[i_rk][C_ACT_CAS]}});
  end

  // Find the row buffer index (the RowIdWidth MSBs) of the optimal entry. The LSBs below this are
  // not regarded, as they map to addresses inside the row.
  logic [RowIdWidth-1:0][MaxNumWEntries+MaxNumREntries-1:0] opti_rbuf_interm[NumRanks];
  logic [RowIdWidth-1:0] opti_rbuf[NumRanks];

  for (genvar i_rk = 0; i_rk < NumRanks; i_rk = i_rk + 1) begin : opti_rbuf_rk
    // The row buffer identifier is obtained bit by bit.
    for (genvar i_rbb = RowBufLenW; i_rbb < GlobalMemCapaW; i_rbb = i_rbb + 1) begin : opti_rbuf_rbb
      // For write entries
      for (genvar i_slt = 0; i_slt < NumWSlots; i_slt = i_slt + 1) begin : opti_rbuf_wslt
        for (genvar i_bit = 0; i_bit < MaxBurstEffLen; i_bit = i_bit + 1) begin : opti_rbuf_wd
          // Take the address bit of a write data entry if it is the optimal entry.
          assign opti_rbuf_interm[i_rk][i_rbb-RowBufLenW][i_slt*MaxBurstEffLen + i_bit] =
              opti_entry_onehot[i_rk][i_slt*MaxBurstEffLen + i_bit] & slt_waddrs[i_slt][i_bit][i_rbb];
        end : opti_rbuf_wd
      end : opti_rbuf_wslt
      // For read entries
      for (genvar i_slt = 0; i_slt < NumRSlots; i_slt = i_slt + 1) begin : opti_rbuf_rslt
        for (genvar i_bit = 0; i_bit < MaxBurstEffLen; i_bit = i_bit + 1) begin : opti_rbuf_rslt_bit
          // Take the address bit of a read data entry if its slot is the optimal entry according to
          // the main age matrix, and if the current entry is the optimal in the slot.
          assign opti_rbuf_interm[i_rk][i_rbb-RowBufLenW][MAgeMRSltStart+i_slt*MaxBurstEffLen+i_bit] =
              opti_entry_onehot[i_rk][MAgeMRSltStart+i_slt] &
              slt_nxt_data_onehot[i_rk][i_slt][i_bit] & slt_raddrs[i_slt][i_bit][i_rbb];
        end : opti_rbuf_rslt_bit
      end : opti_rbuf_rslt

      // Aggregate the bit for all the entries.
      assign opti_rbuf[i_rk][i_rbb-RowBufLenW] = |opti_rbuf_interm[i_rk][i_rbb-RowBufLenW];
    end : opti_rbuf_rbb
  end : opti_rbuf_rk

  //////////////////////////////////////////
  // Find next slot where write data fits //
  //////////////////////////////////////////

  // In this part, the signals indicating in which slot and in which write data entry, a new write
  // data request should fit. If there is no candidate, then refuse incoming write data requests
  // (they will be counted by the delay counter wrapper).
  //
  // The chosen write slot is the oldest occupied write slot whose write data entries are not all
  // valid, if applicable.

  // Slot where the data should fit (binary representation).
  logic [NumWSlots-1:0] free_wslt_for_data_mhot;
  logic [NumWSlots-1:0] free_wslt_for_data_onehot;
  // First non-valid bit in the write slot, for each slot.
  logic [MaxBurstEffLen-1:0] nxt_nv_bit_onehot[NumWSlots];

  // For each write slot, find the lowest-indexed non-valid write data entry in the slot.
  for (genvar i_slt = 0; i_slt < NumWSlots; i_slt = i_slt + 1) begin : gen_slt_for_in_data
    for (genvar i_bit = 0; i_bit < MaxBurstEffLen; i_bit = i_bit + 1) begin : gen_nxt_nv_bit_inner
      if (i_bit == 0) begin
        assign nxt_nv_bit_onehot[i_slt][i_bit] = ~wslt_q[i_slt].data_v[0];
      end else begin
        assign nxt_nv_bit_onehot[i_slt][i_bit] =
            ~wslt_q[i_slt].data_v[i_bit] && &wslt_q[i_slt].data_v[i_bit - 1:0];
      end
    end : gen_nxt_nv_bit_inner
  end : gen_slt_for_in_data

  // Find the oldest slot where data is expected
  for (genvar i_slt = 0; i_slt < NumWSlots; i_slt = i_slt + 1) begin : gen_wslt_for_in_data_onehot
    assign free_wslt_for_data_mhot[i_slt] = wslt_q[i_slt].v & ~&wslt_q[i_slt].data_v;
    assign free_wslt_for_data_onehot[i_slt] =
        free_wslt_for_data_mhot[i_slt] & ~|(wslt_age_matrix[i_slt] & free_wslt_for_data_mhot);
  end : gen_wslt_for_in_data_onehot

  //////////////////////////////////
  // Address calculation in slots //
  //////////////////////////////////

  // In this part, the address corresponding to each entry in each write slot and read slot is
  // calculated from the slot burst base address and burst size. As bursts are aligned, only few
  // bits change between bits of the same burst.

  // Addresses of slot entries.
  logic [GlobalMemCapaW-1:0] slt_waddrs[NumWSlots][MaxBurstEffLen];
  logic [GlobalMemCapaW-1:0] slt_raddrs[NumRSlots][MaxBurstEffLen];

  // Least significant bits of the addresses.
  logic [BurstAddrLSBs-1:0] slt_waddr_lsbs[NumWSlots][MaxBurstEffLen];
  logic [BurstAddrLSBs-1:0] slt_raddr_lsbs[NumRSlots][MaxBurstEffLen];

  // Write data entries address.
  for (genvar i_slt = 0; i_slt < NumWSlots; i_slt = i_slt + 1) begin : gen_waddrs_perslt
    for (genvar i_bit = 0; i_bit < MaxBurstEffLen; i_bit = i_bit + 1) begin : gen_waddrs
      if (i_bit == 0) begin
        assign slt_waddr_lsbs[i_slt][0] = wslt_q[i_slt].addr[BurstAddrLSBs-1:0];
      end else begin
        always_comb begin
          if (wslt_q[i_slt].burst_fixed) begin
            assign slt_waddr_lsbs[i_slt][i_bit] = wslt_q[i_slt].addr[BurstAddrLSBs-1:0];
          end else begin
            assign slt_waddr_lsbs[i_slt][i_bit] = BurstAddrLSBs'(slt_waddr_lsbs[i_slt][i_bit - 1] +
                BurstAddrLSBs'(get_effective_burst_size(AxSizeWidth'(wslt_q[i_slt].burst_size))));
          end
        end
      end

      // Concatenate the MSBs of the base address with the LSBs of each entry to form the whole
      // entries' addresses.
      assign slt_waddrs[i_slt][i_bit] = {
          wslt_q[i_slt].addr[GlobalMemCapaW - 1:BurstAddrLSBs],
          slt_waddr_lsbs[i_slt][i_bit]
        };
    end : gen_waddrs
  end : gen_waddrs_perslt

  // Read data entries address.
  for (genvar i_slt = 0; i_slt < NumRSlots; i_slt = i_slt + 1) begin : gen_raddrs_perslt
    for (genvar i_bit = 0; i_bit < MaxBurstEffLen; i_bit = i_bit + 1) begin : gen_raddrs
      if (i_bit == 0) begin
        assign slt_raddr_lsbs[i_slt][0] = rslt_q[i_slt].addr[BurstAddrLSBs-1:0];
      end else begin
        always_comb begin
          if (rslt_q[i_slt].burst_fixed) begin
            assign slt_raddr_lsbs[i_slt][i_bit] = rslt_q[i_slt].addr[BurstAddrLSBs-1:0];
          end else begin
            assign slt_raddr_lsbs[i_slt][i_bit] = BurstAddrLSBs'(slt_raddr_lsbs[i_slt][i_bit - 1] +
                BurstAddrLSBs'(get_effective_burst_size(AxSizeWidth'(rslt_q[i_slt].burst_size))));
          end
        end
      end

      // Concatenate the MSBs of the base address with the LSBs of each entry to form the whole
      // entries' addresses.
      assign slt_raddrs[i_slt][i_bit] = {
        rslt_q[i_slt].addr[GlobalMemCapaW - 1:BurstAddrLSBs],
        slt_raddr_lsbs[i_slt][i_bit]
      };
    end : gen_raddrs
  end : gen_raddrs_perslt

  //////////////////
  // Rank signals //
  //////////////////

  // The ranks are simulated by counters. These counters are set to a given request cost and
  // constantly decremented to zero.

  // Determines if there is a row open in the rank. So far, this is always true after the first
  // request.
  logic is_row_open_d[NumRanks];
  logic is_row_open_q[NumRanks];

  // Determines the start address of the open row. This is useful for request cost calculation. If
  // no row is open in the rank, then this value is irrelevant.
  logic [RowIdWidth-1:0] row_buf_ident_d[NumRanks];
  logic [RowIdWidth-1:0] row_buf_ident_q[NumRanks];

  // Decreasing counter that determines the number of cycles in which the rank will be able to take
  // a new request.
  logic [DelayW-1:0] rank_delay_cnt_d[NumRanks];
  logic [DelayW-1:0] rank_delay_cnt_q[NumRanks];

  /////////////
  // Outputs //
  /////////////

  // The output *_release_en_mhot_o signals enable the release of some addresses (aka. iids) by the
  // response banks. As there is only one output fired per write burst, a single one-hot row of
  // flip-flops is sufficient for the wrsp_release_en signal. Counters are useful, however, for read
  // data, which are subject to burst responses.

  logic [WRspBankCapa-1:0] wrsp_release_en_mhot_d;
  logic [RDataBankCapa-1:0][MaxBurstLenField-1:0] rdata_release_en_cnts_d;
  logic [RDataBankCapa-1:0][MaxBurstLenField-1:0] rdata_release_en_cnts_q;

  // Set the read data release_en outputs to one, where the corresponding counter is not zero.
  for (genvar i_iid = 0; i_iid < RDataBankCapa; i_iid = i_iid + 1) begin : en_rdata_release
    assign rdata_release_en_mhot_o[i_iid] = |rdata_release_en_cnts_q[i_iid];
  end : en_rdata_release

  ////////////////////////////////////
  // Management combinatorial logic //
  ////////////////////////////////////

  // Delay calculator management logic
  always_comb begin

    // Default assignments
    for (int unsigned i_rk = 0; i_rk < NumRanks; i_rk = i_rk + 1) begin
      is_row_open_d[i_rk] = is_row_open_q[i_rk];
      row_buf_ident_d[i_rk] = row_buf_ident_q[i_rk];
    end

    wrsp_release_en_mhot_d = wrsp_release_en_mhot_o;
    rdata_release_en_cnts_d = rdata_release_en_cnts_q;

    main_new_entry = '{default: '0};
    wslt_new_entry = '{default: '0};


    ////////////////////////////
    // Address requests input //
    ////////////////////////////

    // This part is dedicated to the the acceptation of write or read address requests.

    // To favor read requests, swap this part with the following part.

    // Write address request input.
    for (int unsigned i_slt = 0; i_slt < NumWSlots; i_slt = i_slt + 1) begin
      // By default, keep the slots' previous value.
      wslt_d[i_slt] = wslt_q[i_slt];

      if (waddr_valid_i && waddr_ready_o && nxt_free_wslt_onehot[i_slt]) begin
        // If there is a successful write address handshake and i_slt has been determined to be its
        // home slot, then fill the slot with the relevant information from the write address
        // request.
        wslt_d[i_slt].v = 1'b1;
        wslt_d[i_slt].iid = waddr_iid_i;
        wslt_d[i_slt].addr = waddr_i.addr;

        // Support for fixed bursts is provided by setting a burst size of 0.
        wslt_d[i_slt].burst_size = waddr_i.burst_size;
        wslt_d[i_slt].burst_fixed = waddr_i.burst_type == BURST_FIXED;

        // The mem_pending bits of a new request are always set to zero, until an access to the
        // corresponding rank is simulated.
        wslt_d[i_slt].mem_pending = '0;

        // Update the write slot age matrix.
        wslt_new_entry[i_slt] = 1'b1;

        // Fill the write data entries.
        for (int unsigned i_bit = 0; i_bit < MaxBurstEffLen; i_bit = i_bit + 1) begin
          // The first wdata_immediate_cnt_i data_v bits are set to 1'b1, as they are occupied by
          // the immediately present write data requests, that come simultaneously with the write
          // address request. Some of the last data_v bits, which correspond to the bits beyond the
          // write address request's burst length, are also set to 1'b1, as they will not expect any
          // write data to come in. The rest of the data_v bits (between the two possibly empty
          // ranges of ones) are set to zero, awaiting further write data requests.
          wslt_d[i_slt].data_v[i_bit] =
              (i_bit >= get_effective_burst_len(AxLenWidth'(waddr_i.burst_len))) || (i_bit < get_effective_burst_len(AxLenWidth'(wdata_immediate_cnt_i)));
          // The age matrix has to be updated for each immediate write data, with the same age
          // relative to the entries external to the slot.
          main_new_entry[i_slt * MaxBurstEffLen+i_bit] = i_bit < wdata_immediate_cnt_i;
          // Some of the last mem_done bits, which correspond to the bits beyond the write address
          // request's burst length, are set to 1'b1, as they are considered already treated (will
          // never be treated further, and the slot is considered complete when all the mem_done
          // bits are set to one). The rest of the mem_done bits are set to zero, and will be set to
          // one later when a transaction is complete.
          wslt_d[i_slt].mem_done[i_bit] = i_bit >= get_effective_burst_len(AxLenWidth'(waddr_i.burst_len));
        end
      end
    end


    //////////////////////////////
    // Write data request input //
    //////////////////////////////

    // This part is dedicated to the acceptance of write data  requests when there are some occupied
    // but incomplete write slots (i.e., write addresses with some missing write_data corresponding
    // to the burst).

    for (int unsigned i_slt = 0; i_slt < NumWSlots; i_slt = i_slt + 1) begin
      for (int unsigned i_bit = 0; i_bit < MaxBurstEffLen; i_bit = i_bit + 1) begin
        if (nxt_nv_bit_onehot[i_slt][i_bit] && free_wslt_for_data_onehot[i_slt]  &&
            wdata_valid_i) begin
          // The data_v signal is OR-masked with a mask determining where the new data should land.
          // Most of the times, the mask is full-zero, as there is no write data input handshake or
          // because this is not the slot where the write data where it should land.
          wslt_d[i_slt].data_v[i_bit] = 1'b1;
          main_new_entry[i_slt * MaxBurstEffLen+i_bit] = 1'b1;
        end
      end
    end

    // To favor read requests, swap this part with the previous part.

    // Read address request input.
    for (int unsigned i_slt = 0; i_slt < NumRSlots; i_slt = i_slt + 1) begin
      // By default, keep the slots' previous value.
      rslt_d[i_slt] = rslt_q[i_slt];

      if (raddr_valid_i && raddr_ready_o && nxt_free_rslt_onehot[i_slt]) begin
        // If there is a successful write address handshake and i_slt has been determined to be its
        // home slot, then fill the slot with the relevant information from the write address
        // request.
        rslt_d[i_slt].v = 1'b1;
        rslt_d[i_slt].iid = raddr_iid_i;
        rslt_d[i_slt].addr = raddr_i.addr;

        // Support for fixed bursts is provided by setting a burst size of 0.
        rslt_d[i_slt].burst_size = raddr_i.burst_size;
        rslt_d[i_slt].burst_fixed = raddr_i.burst_type == BURST_FIXED;

        // The mem_pending bits of a new request are always set to zero, until an access to the
        // corresponding rank is simulated.
        rslt_d[i_slt].mem_pending = '0;

        for (int unsigned i_bit = 0; i_bit < MaxBurstEffLen; i_bit = i_bit + 1) begin
          // Some of the last mem_done bits, which correspond to the bits beyond the read address
          // request's burst length, are set to 1'b1, as they are considered already treated (will
          // never be treated further, and the slot is considered complete when all the mem_done
          // bits are set to one). The rest of the mem_done bits are set to zero, and will be set to
          // one later when a transaction is complete.
          rslt_d[i_slt].mem_done[i_bit] = i_bit >= get_effective_burst_len(AxLenWidth'(raddr_i.burst_len));
        end

        main_new_entry[MAgeMRSltStart + i_slt] = 1'b1;
      end
    end

    // To favor read requests, swap until here.

    ///////////////////////
    // Rank state update //
    ///////////////////////

    // This part is dedicated to updating the rank counters and row state signals.

    // If the rank counter is not zero, then simply decrement it.
    for (int unsigned i_rk = 0; i_rk < NumRanks; i_rk = i_rk + 1) begin
      if (rank_delay_cnt_q[i_rk] != 0) begin
        // A row is now open in the corresponding rank.
        is_row_open_d[i_rk] = 1'b1;

        rank_delay_cnt_d[i_rk] = rank_delay_cnt_q[i_rk] - 1;
      end else begin
        // The case where rank_delay_cnt_q has to remain zero is treated through COST_NO_CANDIDATE.
        rank_delay_cnt_d[i_rk] = decategorize_mem_cost(opti_cost_cat[i_rk]);

        // Set the memory pending bit in the case of a write data entry.
        for (int unsigned i_slt = 0; i_slt < NumWSlots; i_slt = i_slt + 1) begin
          wslt_d[i_slt].mem_pending |= opti_entry_onehot[i_rk][i_slt*MaxBurstEffLen +: MaxBurstEffLen];
        end
        // Set the memory pending bit in the case of a read data entry.
        for (int unsigned i_slt = 0; i_slt < NumRSlots; i_slt = i_slt + 1) begin
          rslt_d[i_slt].mem_pending |=
              {MaxBurstEffLen{opti_entry_onehot[i_rk][MAgeMRSltStart+i_slt]}} &
                  slt_nxt_data_onehot[i_rk][i_slt];
        end

        // Update the row start address.
        row_buf_ident_d[i_rk] = opti_rbuf[i_rk];
      end
    end


    /////////////////////////////////////////
    // Entry request completion management //
    /////////////////////////////////////////

    // This part is dedicated to managing the completion of requests. A request is said complete
    // when its corresponding mem_done is set to one. It is either completed immediately at slot
    // occupation if this is an excess request (a data request which is beyond the actual address
    // request's burst length). Else, the corresponding mem_done bit is set to one when the mem_done
    // bit is one, and the corresponding rank counter hits zero (plus a certain constant delay to
    // accommodate the non-zero delay until the simulated memory controller's output).

    // Updated at delay 3 to accommodate the one-cycle additional latency due to the response bank.
    for (int unsigned i_rk = 0; i_rk < NumRanks; i_rk = i_rk + 1) begin
      if (rank_delay_cnt_q[i_rk] == 3) begin
        for (int unsigned i_slt = 0; i_slt < NumWSlots; i_slt = i_slt + 1) begin
          for (int unsigned i_bit = 0; i_bit < MaxBurstEffLen; i_bit = i_bit + 1) begin
            // Mark memory operation done if already done, or was pending.
            wslt_d[i_slt].mem_done[i_bit] = wslt_q[i_slt].mem_done[i_bit] |
                (wslt_q[i_slt].mem_pending[i_bit] &
                (get_assigned_rk_id(slt_waddrs[i_slt][i_bit])==NumRksW'(i_rk)));
            // Unset the potential corresponding memory pending bit.
            wslt_d[i_slt].mem_pending[i_bit] = wslt_d[i_slt].mem_pending[i_bit] &
                get_assigned_rk_id(slt_waddrs[i_slt][i_bit])!=NumRksW'(i_rk);
          end
        end
        for (int unsigned i_slt = 0; i_slt < NumRSlots; i_slt = i_slt + 1) begin
          for (int unsigned i_bit = 0; i_bit < MaxBurstEffLen; i_bit = i_bit + 1) begin
            // Mark memory operation done if already done, or was pending.
            rslt_d[i_slt].mem_done[i_bit] = rslt_q[i_slt].mem_done[i_bit] |
                (rslt_q[i_slt].mem_pending[i_bit] &
                (get_assigned_rk_id(slt_raddrs[i_slt][i_bit])==NumRksW'(i_rk)));
            // Unset the potential corresponding memory pending bit.
            rslt_d[i_slt].mem_pending[i_bit] = rslt_d[i_slt].mem_pending[i_bit] &
                get_assigned_rk_id(slt_raddrs[i_slt][i_bit])!=NumRksW'(i_rk);
          end
        end
      end
    end

    // Input signals from message banks about released signals
    wrsp_release_en_mhot_d ^= wrsp_released_iid_onehot_i;

    // Decrement the rdata_release_en_cnts_d if data has been released for this address (aka. iid).
    // If a counter is decremented, it was originally not zero, because a message bank is not
    // allowed to release read responses of the corresponding rdata_release_en_mhot_o bit is zero,
    // which happens iff the corresponding counter is zero.
    for (int unsigned i_iid = 0; i_iid < RDataBankCapa; i_iid = i_iid + 1) begin
      if (rdata_released_iid_onehot_i[i_iid]) begin
        rdata_release_en_cnts_d[i_iid] -= 1;
      end
    end


    /////////////////////
    // Slot liberation //
    /////////////////////

    // This part is dedicated to free complete slots and notify the outputs in thiis case.

    // Write slots
    for (int unsigned i_slt = 0; i_slt < NumWSlots; i_slt = i_slt + 1) begin
      // If all the memory requests of a burst have been satisfied, then free the slot.
      wslt_d[i_slt].v &= ~&wslt_q[i_slt].mem_done;
      for (int unsigned i_iid = 0; i_iid < WRspBankCapa; i_iid = i_iid + 1) begin
        // If all the memory requests of a burst have been satisfied, then notify the output.
        if (wslt_q[i_slt].v && &wslt_q[i_slt].mem_done) begin
          wrsp_release_en_mhot_d[i_iid] |= wslt_q[i_slt].iid == WRspBankAddrW'(i_iid);
          // Set mem_done to zero when all requests in the burst have complete.
          wslt_d[i_slt].mem_done = '0;
        end
      end
    end
    // Read slots
    for (int unsigned i_slt = 0; i_slt < NumRSlots; i_slt = i_slt + 1) begin
      // If all the memory requests of a burst have been satisfied, then free the slot.

      rslt_d[i_slt].v &= ~&rslt_q[i_slt].mem_done;
      for (int unsigned i_iid = 0; i_iid < RDataBankCapa; i_iid = i_iid + 1) begin
        // For each individual read data, enable its release as soon as it has been marked for
        // release.
        for (int unsigned i_bit = 0; i_bit < MaxBurstEffLen; i_bit = i_bit + 1) begin
          if (rslt_q[i_slt].v && (rslt_q[i_slt].mem_pending[i_bit] && rslt_d[i_slt].mem_done[i_bit] &&
              rslt_q[i_slt].iid == RDataBankAddrW'(i_iid))) begin
            rdata_release_en_cnts_d[i_iid] += 1;
          end
        end
        // Set mem_done to zero when all requests in the burst has complete.
        if (rslt_q[i_slt].v && &rslt_q[i_slt].mem_done) begin
          rslt_d[i_slt].mem_done = '0;
        end
      end
    end
  end

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      wslt_q <= '{default: '0};
      rslt_q <= '{default: '0};
      is_row_open_q <= '{default: '0};
      row_buf_ident_q <= '{default: '0};
      rank_delay_cnt_q <= '{default: '0};
      wrsp_release_en_mhot_o <= '0;
      rdata_release_en_cnts_q <= '0;
    end else begin
      wslt_q <= wslt_d;
      rslt_q <= rslt_d;
      is_row_open_q <= is_row_open_d;
      row_buf_ident_q <= row_buf_ident_d;
      rank_delay_cnt_q <= rank_delay_cnt_d;
      wrsp_release_en_mhot_o <= wrsp_release_en_mhot_d;
      rdata_release_en_cnts_q <= rdata_release_en_cnts_d;
    end
  end

endmodule
