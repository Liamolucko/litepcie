// This file is part of LitePCIe.
//
// Copyright (c) 2020-2023 Enjoy-Digital <enjoy-digital.fr>
// SPDX-License-Identifier: BSD-2-Clause

module s_axis_rq_adapt # (
      parameter DATA_WIDTH  = 128,
      parameter KEEP_WIDTH  = DATA_WIDTH/8
    )(

       input user_clk,
       input user_reset,

       output [DATA_WIDTH-1:0] s_axis_rq_tdata,
       output [KEEP_WIDTH-1:0] s_axis_rq_tkeep,
       output                  s_axis_rq_tlast,
       input             [3:0] s_axis_rq_tready,
       output            [3:0] s_axis_rq_tuser,
       output                  s_axis_rq_tvalid,

       input   [DATA_WIDTH-1:0] s_axis_rq_tdata_a,
       input   [KEEP_WIDTH-1:0] s_axis_rq_tkeep_a,
       input                    s_axis_rq_tlast_a,
       output             [3:0] s_axis_rq_tready_a,
       input              [3:0] s_axis_rq_tuser_a,
       input                    s_axis_rq_tvalid_a
    );

 wire          s_axis_rq_tready_ff,
                s_axis_rq_tvalid_ff,
                s_axis_rq_tlast_ff;
  wire [7:0]    s_axis_rq_tkeep_or = {s_axis_rq_tkeep[28], s_axis_rq_tkeep[24], s_axis_rq_tkeep[20], s_axis_rq_tkeep[16],
                                      s_axis_rq_tkeep[12], s_axis_rq_tkeep[8], s_axis_rq_tkeep[4], s_axis_rq_tkeep[0]};

  wire [3:0]    s_axis_rq_tuser_ff;
  wire [7:0]    s_axis_rq_tkeep_ff;
  wire [255:0]  s_axis_rq_tdata_ff;

  axis_iff #(.DAT_B(256+8+4))  s_axis_rq_iff
  (
        .clk    (user_clk),
        .rst    (user_reset),

        .i_vld  (s_axis_rq_tvalid),
        .o_rdy  (s_axis_rq_tready),
        .i_sop  (1'b0),
        .i_eop  (s_axis_rq_tlast),
        .i_dat  ({s_axis_rq_tuser, s_axis_rq_tkeep_or, s_axis_rq_tdata}),

        .o_vld  (s_axis_rq_tvalid_ff),
        .i_rdy  (s_axis_rq_tready_ff),
        .o_sop  (),
        .o_eop  (s_axis_rq_tlast_ff),
        .o_dat  ({s_axis_rq_tuser_ff, s_axis_rq_tkeep_ff, s_axis_rq_tdata_ff})
    );


  reg [1:0]       s_axis_rq_cnt;  //0-2
  always @(posedge user_clk)
      if (user_reset) s_axis_rq_cnt <= 2'd0;
      else if (s_axis_rq_tvalid_ff && s_axis_rq_tready_ff)
          begin
              if (s_axis_rq_tlast_ff) s_axis_rq_cnt <= 2'd0;
              else if (!s_axis_rq_cnt[1]) s_axis_rq_cnt <= s_axis_rq_cnt + 1;
          end

  wire            s_axis_rq_tfirst = (s_axis_rq_cnt == 0) && (!s_axis_rq_tlast_lat);
  wire            s_axis_rq_tsecond = s_axis_rq_cnt == 1;

  //processing for tlast: generate new last in case write & last num of dword = 5 + i*8
  wire            s_axis_rq_read = (s_axis_rq_tdata_ff[31:30] == 2'b0);  //Read request
  wire            s_axis_rq_write = !s_axis_rq_read;
  reg             s_axis_rq_tlast_dly_en;
  reg             s_axis_rq_tlast_lat;
  wire [3:0]      s_axis_rq_tready_a;
  always @(posedge user_clk)
      if (user_reset) s_axis_rq_tlast_dly_en <= 1'd0;
      else if (s_axis_rq_tvalid_ff && s_axis_rq_tfirst && s_axis_rq_write) s_axis_rq_tlast_dly_en <= (s_axis_rq_tdata_ff[2:0] == 3'b101);

  always @(posedge user_clk)
      if (user_reset) s_axis_rq_tlast_lat <= 1'd0;
      else if (s_axis_rq_tlast_lat && s_axis_rq_tready_a[0]) s_axis_rq_tlast_lat <= 1'd0;
      else if (s_axis_rq_tvalid_ff && s_axis_rq_tlast_ff && s_axis_rq_tready_a[0])
          begin
          if (s_axis_rq_tfirst) s_axis_rq_tlast_lat <= s_axis_rq_write ? (s_axis_rq_dwlen == 11'd5) : 1'b0; //write 5 dwords
          else s_axis_rq_tlast_lat <= s_axis_rq_tlast_dly_en;
          end

  wire            s_axis_rq_tlast_a  = s_axis_rq_tfirst       ? (s_axis_rq_read | (s_axis_rq_dwlen < 11'd5)) :
                                       s_axis_rq_tlast_dly_en ? s_axis_rq_tlast_lat : s_axis_rq_tlast_ff;

  //Generae ready for TLP
  assign          s_axis_rq_tready_ff = s_axis_rq_tready_a[0] && (!s_axis_rq_tlast_lat);
  wire            s_axis_rq_tvalid_a = s_axis_rq_tvalid_ff | s_axis_rq_tlast_lat;

  wire [10:0]     s_axis_rq_dwlen = {1'b0, s_axis_rq_tdata_ff[9:0]};
  wire [3:0]      s_axis_rq_reqtype = {s_axis_rq_tdata_ff[31:30], s_axis_rq_tdata_ff[28:24]} == 7'b0000000 ? 4'b0000 :  //Mem read Request
                                      {s_axis_rq_tdata_ff[31:30], s_axis_rq_tdata_ff[28:24]} == 7'b0000001 ? 4'b0111 :  //Mem Read request-locked
                                      {s_axis_rq_tdata_ff[31:30], s_axis_rq_tdata_ff[28:24]} == 7'b0100000 ? 4'b0001 :  //Mem write request
                                       s_axis_rq_tdata_ff[31:24] == 8'b00000010                           ? 4'b0010 :  //I/O Read request
                                       s_axis_rq_tdata_ff[31:24] == 8'b01000010                           ? 4'b0011 :  //I/O Write request
                                       s_axis_rq_tdata_ff[31:24] == 8'b00000100                           ? 4'b1000 :  //Cfg Read Type 0
                                       s_axis_rq_tdata_ff[31:24] == 8'b01000100                           ? 4'b1010 :  //Cfg Write Type 0
                                       s_axis_rq_tdata_ff[31:24] == 8'b00000101                           ? 4'b1001 :  //Cfg Read Type 1
                                       s_axis_rq_tdata_ff[31:24] == 8'b01000101                           ? 4'b1011 :  //Cfg Write Type 1
                                                                                                          4'b1111;
  wire            s_axis_rq_poisoning = s_axis_rq_tdata_ff[14] | s_axis_rq_tuser_ff[1];   //EP must be 0 for request
  wire [15:0]     s_axis_rq_requesterid = s_axis_rq_tdata_ff[63:48];
  wire [7:0]      s_axis_rq_tag = s_axis_rq_tdata_ff[47:40];
  wire [15:0]     s_axis_rq_completerid = 16'b0;   //applicable only to Configuration requests and messages routed by ID
  wire            s_axis_rq_requester_en = 1'b0;   //Must be 0 for Endpoint
  wire [2:0]      s_axis_rq_tc = s_axis_rq_tdata_ff[22:20];
  wire [2:0]      s_axis_rq_attr = {1'b0, s_axis_rq_tdata_ff[13:12]};
  wire            s_axis_rq_ecrc = s_axis_rq_tdata_ff[15] | s_axis_rq_tuser_ff[0];     //TLP Digest

  wire [63:0]     s_axis_rq_tdata_header  = {s_axis_rq_ecrc,
                                             s_axis_rq_attr,
                                             s_axis_rq_tc,
                                             s_axis_rq_requester_en,
                                             s_axis_rq_completerid,
                                             s_axis_rq_tag,
                                             s_axis_rq_requesterid,
                                             s_axis_rq_poisoning, s_axis_rq_reqtype, s_axis_rq_dwlen};

  wire [3:0]      s_axis_rq_firstbe = s_axis_rq_tdata_ff[35:32];
  wire [3:0]      s_axis_rq_lastbe = s_axis_rq_tdata_ff[39:36];
  reg  [3:0]      s_axis_rq_firstbe_l;
  reg  [3:0]      s_axis_rq_lastbe_l;

  always @(posedge user_clk)
  begin
      if (s_axis_rq_tvalid_ff && s_axis_rq_tfirst)
          begin
          s_axis_rq_firstbe_l <= s_axis_rq_firstbe;
          s_axis_rq_lastbe_l <= s_axis_rq_lastbe;
          end
      end

  reg [31:0]       s_axis_rq_tdata_l;
  always @(posedge user_clk)
      if (s_axis_rq_tvalid_ff && s_axis_rq_tready_ff)
          s_axis_rq_tdata_l <= s_axis_rq_tdata_ff[255:224];

  wire [255:0]    s_axis_rq_tdata_a  = s_axis_rq_tfirst ? {s_axis_rq_tdata_ff[223:96], s_axis_rq_tdata_header, 32'b0, s_axis_rq_tdata_ff[95:64]} :
                                                          {s_axis_rq_tdata_ff[223:0], s_axis_rq_tdata_l[31:0]};
  wire [7:0]      s_axis_rq_tkeep_a  = s_axis_rq_tlast_lat ? 8'h1 : {s_axis_rq_tkeep_ff[6:0], 1'b1};
  wire [59:0]     s_axis_rq_tuser_a;
  assign          s_axis_rq_tuser_a[59:8] = {32'b0, 4'b0, 1'b0, 8'b0, 2'b0, 1'b0, s_axis_rq_tuser_ff[3], 3'b0};
  assign          s_axis_rq_tuser_a[7:0]  = {s_axis_rq_lastbe, s_axis_rq_firstbe};

endmodule