// Standard header to adapt well known macros to our needs.
`ifdef RANDOMIZE_REG_INIT
  `define RANDOMIZE
`endif

// RANDOM may be set to an expression that produces a 32-bit random unsigned value.
`ifndef RANDOM
  `define RANDOM $random
`endif

// Users can define INIT_RANDOM as general code that gets injected into the
// initializer block for modules with registers.
`ifndef INIT_RANDOM
  `define INIT_RANDOM
`endif

// If using random initialization, you can also define RANDOMIZE_DELAY to
// customize the delay used, otherwise 0.002 is used.
`ifndef RANDOMIZE_DELAY
  `define RANDOMIZE_DELAY 0.002
`endif

// Define INIT_RANDOM_PROLOG_ for use in our modules below.
`ifdef RANDOMIZE
  `ifdef VERILATOR
    `define INIT_RANDOM_PROLOG_ `INIT_RANDOM
  `else
    `define INIT_RANDOM_PROLOG_ `INIT_RANDOM #`RANDOMIZE_DELAY begin end
  `endif
`else
  `define INIT_RANDOM_PROLOG_
`endif

module tuples(	// ../tmp/unpack.mlir:4:1
  input         in0_valid,
  input  [31:0] in0_data_field0,
                in0_data_field1,
                in0_data_field2,
                in0_data_field3,
                in0_data_field4,
                in0_data_field5,
                in0_data_field6,
                in0_data_field7,
                in0_data_field8,
                in0_data_field9,
                in0_data_field10,
                in0_data_field11,
                in0_data_field12,
                in0_data_field13,
                in0_data_field14,
                in0_data_field15,
  input         inCtrl_valid,
                out0_ready,
                outCtrl_ready,
                clock,
                reset,
  output        in0_ready,
                inCtrl_ready,
                out0_valid,
  output [31:0] out0_data,
  output        outCtrl_valid);

  stream_map stream_map0 (	// ../tmp/unpack.mlir:5:10
    .in0_valid        (in0_valid),
    .in0_data_field0  (in0_data_field0),
    .in0_data_field1  (in0_data_field1),
    .in0_data_field2  (in0_data_field2),
    .in0_data_field3  (in0_data_field3),
    .in0_data_field4  (in0_data_field4),
    .in0_data_field5  (in0_data_field5),
    .in0_data_field6  (in0_data_field6),
    .in0_data_field7  (in0_data_field7),
    .in0_data_field8  (in0_data_field8),
    .in0_data_field9  (in0_data_field9),
    .in0_data_field10 (in0_data_field10),
    .in0_data_field11 (in0_data_field11),
    .in0_data_field12 (in0_data_field12),
    .in0_data_field13 (in0_data_field13),
    .in0_data_field14 (in0_data_field14),
    .in0_data_field15 (in0_data_field15),
    .inCtrl_valid     (inCtrl_valid),
    .out0_ready       (out0_ready),
    .outCtrl_ready    (outCtrl_ready),
    .clock            (clock),
    .reset            (reset),
    .in0_ready        (in0_ready),
    .inCtrl_ready     (inCtrl_ready),
    .out0_valid       (out0_valid),
    .out0_data        (out0_data),
    .outCtrl_valid    (outCtrl_valid)
  );
endmodule

module handshake_unpack_in_tuple_ui32_ui32_ui32_ui32_ui32_ui32_ui32_ui32_ui32_ui32_ui32_ui32_ui32_ui32_ui32_ui32_out_ui32_ui32_ui32_ui32_ui32_ui32_ui32_ui32_ui32_ui32_ui32_ui32_ui32_ui32_ui32_ui32(
  input         in0_valid,
  input  [31:0] in0_data_field0,
                in0_data_field1,
                in0_data_field2,
                in0_data_field3,
                in0_data_field4,
                in0_data_field5,
                in0_data_field6,
                in0_data_field7,
                in0_data_field8,
                in0_data_field9,
                in0_data_field10,
                in0_data_field11,
                in0_data_field12,
                in0_data_field13,
                in0_data_field14,
                in0_data_field15,
  input         out0_ready,
                out1_ready,
                out2_ready,
                out3_ready,
                out4_ready,
                out5_ready,
                out6_ready,
                out7_ready,
                out8_ready,
                out9_ready,
                out10_ready,
                out11_ready,
                out12_ready,
                out13_ready,
                out14_ready,
                out15_ready,
                clock,
                reset,
  output        in0_ready,
                out0_valid,
  output [31:0] out0_data,
  output        out1_valid,
  output [31:0] out1_data,
  output        out2_valid,
  output [31:0] out2_data,
  output        out3_valid,
  output [31:0] out3_data,
  output        out4_valid,
  output [31:0] out4_data,
  output        out5_valid,
  output [31:0] out5_data,
  output        out6_valid,
  output [31:0] out6_data,
  output        out7_valid,
  output [31:0] out7_data,
  output        out8_valid,
  output [31:0] out8_data,
  output        out9_valid,
  output [31:0] out9_data,
  output        out10_valid,
  output [31:0] out10_data,
  output        out11_valid,
  output [31:0] out11_data,
  output        out12_valid,
  output [31:0] out12_data,
  output        out13_valid,
  output [31:0] out13_data,
  output        out14_valid,
  output [31:0] out14_data,
  output        out15_valid,
  output [31:0] out15_data);

  wire _GEN;
  wire _GEN_0;
  wire _GEN_1;
  wire _GEN_2;
  wire _GEN_3;
  wire _GEN_4;
  wire _GEN_5;
  wire _GEN_6;
  wire _GEN_7;
  wire _GEN_8;
  wire _GEN_9;
  wire _GEN_10;
  wire _GEN_11;
  wire _GEN_12;
  wire _GEN_13;
  wire _GEN_14;
  reg  emtd0;
  reg  emtd1;
  reg  emtd2;
  reg  emtd3;
  reg  emtd4;
  reg  emtd5;
  reg  emtd6;
  reg  emtd7;
  reg  emtd8;
  reg  emtd9;
  reg  emtd10;
  reg  emtd11;
  reg  emtd12;
  reg  emtd13;
  reg  emtd14;
  reg  emtd15;

  wire _GEN_15 = _GEN & _GEN_0 & _GEN_1 & _GEN_2 & _GEN_3 & _GEN_4 & _GEN_5 & _GEN_6 & _GEN_7 & _GEN_8 &
                _GEN_9 & _GEN_10 & _GEN_11 & _GEN_12 & _GEN_13 & _GEN_14;
  wire _GEN_16 = ~emtd0 & in0_valid;
  assign _GEN_14 = out0_ready & _GEN_16 | emtd0;
  wire _GEN_17 = ~emtd1 & in0_valid;
  assign _GEN_13 = out1_ready & _GEN_17 | emtd1;
  wire _GEN_18 = ~emtd2 & in0_valid;
  assign _GEN_12 = out2_ready & _GEN_18 | emtd2;
  wire _GEN_19 = ~emtd3 & in0_valid;
  assign _GEN_11 = out3_ready & _GEN_19 | emtd3;
  wire _GEN_20 = ~emtd4 & in0_valid;
  assign _GEN_10 = out4_ready & _GEN_20 | emtd4;
  wire _GEN_21 = ~emtd5 & in0_valid;
  assign _GEN_9 = out5_ready & _GEN_21 | emtd5;
  wire _GEN_22 = ~emtd6 & in0_valid;
  assign _GEN_8 = out6_ready & _GEN_22 | emtd6;
  wire _GEN_23 = ~emtd7 & in0_valid;
  assign _GEN_7 = out7_ready & _GEN_23 | emtd7;
  wire _GEN_24 = ~emtd8 & in0_valid;
  assign _GEN_6 = out8_ready & _GEN_24 | emtd8;
  wire _GEN_25 = ~emtd9 & in0_valid;
  assign _GEN_5 = out9_ready & _GEN_25 | emtd9;
  wire _GEN_26 = ~emtd10 & in0_valid;
  assign _GEN_4 = out10_ready & _GEN_26 | emtd10;
  wire _GEN_27 = ~emtd11 & in0_valid;
  assign _GEN_3 = out11_ready & _GEN_27 | emtd11;
  wire _GEN_28 = ~emtd12 & in0_valid;
  assign _GEN_2 = out12_ready & _GEN_28 | emtd12;
  wire _GEN_29 = ~emtd13 & in0_valid;
  assign _GEN_1 = out13_ready & _GEN_29 | emtd13;
  wire _GEN_30 = ~emtd14 & in0_valid;
  assign _GEN_0 = out14_ready & _GEN_30 | emtd14;
  `ifndef SYNTHESIS
    `ifdef RANDOMIZE_REG_INIT
      reg [31:0] _RANDOM;

    `endif
    initial begin
      `INIT_RANDOM_PROLOG_
      `ifdef RANDOMIZE_REG_INIT
        _RANDOM = {`RANDOM};
        emtd0 = _RANDOM[0];
        emtd1 = _RANDOM[1];
        emtd2 = _RANDOM[2];
        emtd3 = _RANDOM[3];
        emtd4 = _RANDOM[4];
        emtd5 = _RANDOM[5];
        emtd6 = _RANDOM[6];
        emtd7 = _RANDOM[7];
        emtd8 = _RANDOM[8];
        emtd9 = _RANDOM[9];
        emtd10 = _RANDOM[10];
        emtd11 = _RANDOM[11];
        emtd12 = _RANDOM[12];
        emtd13 = _RANDOM[13];
        emtd14 = _RANDOM[14];
        emtd15 = _RANDOM[15];
      `endif
    end // initial
  `endif
  always @(posedge clock) begin
    if (reset) begin
      emtd0 <= 1'h0;
      emtd1 <= 1'h0;
      emtd2 <= 1'h0;
      emtd3 <= 1'h0;
      emtd4 <= 1'h0;
      emtd5 <= 1'h0;
      emtd6 <= 1'h0;
      emtd7 <= 1'h0;
      emtd8 <= 1'h0;
      emtd9 <= 1'h0;
      emtd10 <= 1'h0;
      emtd11 <= 1'h0;
      emtd12 <= 1'h0;
      emtd13 <= 1'h0;
      emtd14 <= 1'h0;
      emtd15 <= 1'h0;
    end
    else begin
      emtd0 <= _GEN_14 & ~_GEN_15;
      emtd1 <= _GEN_13 & ~_GEN_15;
      emtd2 <= _GEN_12 & ~_GEN_15;
      emtd3 <= _GEN_11 & ~_GEN_15;
      emtd4 <= _GEN_10 & ~_GEN_15;
      emtd5 <= _GEN_9 & ~_GEN_15;
      emtd6 <= _GEN_8 & ~_GEN_15;
      emtd7 <= _GEN_7 & ~_GEN_15;
      emtd8 <= _GEN_6 & ~_GEN_15;
      emtd9 <= _GEN_5 & ~_GEN_15;
      emtd10 <= _GEN_4 & ~_GEN_15;
      emtd11 <= _GEN_3 & ~_GEN_15;
      emtd12 <= _GEN_2 & ~_GEN_15;
      emtd13 <= _GEN_1 & ~_GEN_15;
      emtd14 <= _GEN_0 & ~_GEN_15;
      emtd15 <= _GEN & ~_GEN_15;
    end
  end // always @(posedge)
      wire _GEN_31 = ~emtd15 & in0_valid;
  assign _GEN = out15_ready & _GEN_31 | emtd15;
  assign in0_ready = _GEN_15;
  assign out0_valid = _GEN_16;
  assign out0_data = in0_data_field0;
  assign out1_valid = _GEN_17;
  assign out1_data = in0_data_field1;
  assign out2_valid = _GEN_18;
  assign out2_data = in0_data_field2;
  assign out3_valid = _GEN_19;
  assign out3_data = in0_data_field3;
  assign out4_valid = _GEN_20;
  assign out4_data = in0_data_field4;
  assign out5_valid = _GEN_21;
  assign out5_data = in0_data_field5;
  assign out6_valid = _GEN_22;
  assign out6_data = in0_data_field6;
  assign out7_valid = _GEN_23;
  assign out7_data = in0_data_field7;
  assign out8_valid = _GEN_24;
  assign out8_data = in0_data_field8;
  assign out9_valid = _GEN_25;
  assign out9_data = in0_data_field9;
  assign out10_valid = _GEN_26;
  assign out10_data = in0_data_field10;
  assign out11_valid = _GEN_27;
  assign out11_data = in0_data_field11;
  assign out12_valid = _GEN_28;
  assign out12_data = in0_data_field12;
  assign out13_valid = _GEN_29;
  assign out13_data = in0_data_field13;
  assign out14_valid = _GEN_30;
  assign out14_data = in0_data_field14;
  assign out15_valid = _GEN_31;
  assign out15_data = in0_data_field15;
endmodule

module arith_addi_in_ui32_ui32_out_ui32(
  input         in0_valid,
  input  [31:0] in0_data,
  input         in1_valid,
  input  [31:0] in1_data,
  input         out0_ready,
  output        in0_ready,
                in1_ready,
                out0_valid,
  output [31:0] out0_data);

  wire _GEN = in0_valid & in1_valid;
  wire _GEN_0 = out0_ready & _GEN;
  assign in0_ready = _GEN_0;
  assign in1_ready = _GEN_0;
  assign out0_valid = _GEN;
  assign out0_data = in0_data + in1_data;
endmodule

module stream_map(
  input         in0_valid,
  input  [31:0] in0_data_field0,
                in0_data_field1,
                in0_data_field2,
                in0_data_field3,
                in0_data_field4,
                in0_data_field5,
                in0_data_field6,
                in0_data_field7,
                in0_data_field8,
                in0_data_field9,
                in0_data_field10,
                in0_data_field11,
                in0_data_field12,
                in0_data_field13,
                in0_data_field14,
                in0_data_field15,
  input         inCtrl_valid,
                out0_ready,
                outCtrl_ready,
                clock,
                reset,
  output        in0_ready,
                inCtrl_ready,
                out0_valid,
  output [31:0] out0_data,
  output        outCtrl_valid);

  wire        _arith_addi14_in0_ready;	// ../tmp/unpack.mlir:25:12
  wire        _arith_addi14_in1_ready;	// ../tmp/unpack.mlir:25:12
  wire        _arith_addi13_in0_ready;	// ../tmp/unpack.mlir:23:11
  wire        _arith_addi13_in1_ready;	// ../tmp/unpack.mlir:23:11
  wire        _arith_addi13_out0_valid;	// ../tmp/unpack.mlir:23:11
  wire [31:0] _arith_addi13_out0_data;	// ../tmp/unpack.mlir:23:11
  wire        _arith_addi12_in0_ready;	// ../tmp/unpack.mlir:22:11
  wire        _arith_addi12_in1_ready;	// ../tmp/unpack.mlir:22:11
  wire        _arith_addi12_out0_valid;	// ../tmp/unpack.mlir:22:11
  wire [31:0] _arith_addi12_out0_data;	// ../tmp/unpack.mlir:22:11
  wire        _arith_addi11_in0_ready;	// ../tmp/unpack.mlir:20:11
  wire        _arith_addi11_in1_ready;	// ../tmp/unpack.mlir:20:11
  wire        _arith_addi11_out0_valid;	// ../tmp/unpack.mlir:20:11
  wire [31:0] _arith_addi11_out0_data;	// ../tmp/unpack.mlir:20:11
  wire        _arith_addi10_in0_ready;	// ../tmp/unpack.mlir:19:11
  wire        _arith_addi10_in1_ready;	// ../tmp/unpack.mlir:19:11
  wire        _arith_addi10_out0_valid;	// ../tmp/unpack.mlir:19:11
  wire [31:0] _arith_addi10_out0_data;	// ../tmp/unpack.mlir:19:11
  wire        _arith_addi9_in0_ready;	// ../tmp/unpack.mlir:18:11
  wire        _arith_addi9_in1_ready;	// ../tmp/unpack.mlir:18:11
  wire        _arith_addi9_out0_valid;	// ../tmp/unpack.mlir:18:11
  wire [31:0] _arith_addi9_out0_data;	// ../tmp/unpack.mlir:18:11
  wire        _arith_addi8_in0_ready;	// ../tmp/unpack.mlir:17:11
  wire        _arith_addi8_in1_ready;	// ../tmp/unpack.mlir:17:11
  wire        _arith_addi8_out0_valid;	// ../tmp/unpack.mlir:17:11
  wire [31:0] _arith_addi8_out0_data;	// ../tmp/unpack.mlir:17:11
  wire        _arith_addi7_in0_ready;	// ../tmp/unpack.mlir:15:11
  wire        _arith_addi7_in1_ready;	// ../tmp/unpack.mlir:15:11
  wire        _arith_addi7_out0_valid;	// ../tmp/unpack.mlir:15:11
  wire [31:0] _arith_addi7_out0_data;	// ../tmp/unpack.mlir:15:11
  wire        _arith_addi6_in0_ready;	// ../tmp/unpack.mlir:14:11
  wire        _arith_addi6_in1_ready;	// ../tmp/unpack.mlir:14:11
  wire        _arith_addi6_out0_valid;	// ../tmp/unpack.mlir:14:11
  wire [31:0] _arith_addi6_out0_data;	// ../tmp/unpack.mlir:14:11
  wire        _arith_addi5_in0_ready;	// ../tmp/unpack.mlir:13:11
  wire        _arith_addi5_in1_ready;	// ../tmp/unpack.mlir:13:11
  wire        _arith_addi5_out0_valid;	// ../tmp/unpack.mlir:13:11
  wire [31:0] _arith_addi5_out0_data;	// ../tmp/unpack.mlir:13:11
  wire        _arith_addi4_in0_ready;	// ../tmp/unpack.mlir:12:11
  wire        _arith_addi4_in1_ready;	// ../tmp/unpack.mlir:12:11
  wire        _arith_addi4_out0_valid;	// ../tmp/unpack.mlir:12:11
  wire [31:0] _arith_addi4_out0_data;	// ../tmp/unpack.mlir:12:11
  wire        _arith_addi3_in0_ready;	// ../tmp/unpack.mlir:11:11
  wire        _arith_addi3_in1_ready;	// ../tmp/unpack.mlir:11:11
  wire        _arith_addi3_out0_valid;	// ../tmp/unpack.mlir:11:11
  wire [31:0] _arith_addi3_out0_data;	// ../tmp/unpack.mlir:11:11
  wire        _arith_addi2_in0_ready;	// ../tmp/unpack.mlir:10:11
  wire        _arith_addi2_in1_ready;	// ../tmp/unpack.mlir:10:11
  wire        _arith_addi2_out0_valid;	// ../tmp/unpack.mlir:10:11
  wire [31:0] _arith_addi2_out0_data;	// ../tmp/unpack.mlir:10:11
  wire        _arith_addi1_in0_ready;	// ../tmp/unpack.mlir:9:11
  wire        _arith_addi1_in1_ready;	// ../tmp/unpack.mlir:9:11
  wire        _arith_addi1_out0_valid;	// ../tmp/unpack.mlir:9:11
  wire [31:0] _arith_addi1_out0_data;	// ../tmp/unpack.mlir:9:11
  wire        _arith_addi0_in0_ready;	// ../tmp/unpack.mlir:8:11
  wire        _arith_addi0_in1_ready;	// ../tmp/unpack.mlir:8:11
  wire        _arith_addi0_out0_valid;	// ../tmp/unpack.mlir:8:11
  wire [31:0] _arith_addi0_out0_data;	// ../tmp/unpack.mlir:8:11
  wire        _handshake_unpack0_out0_valid;	// ../tmp/unpack.mlir:7:14
  wire [31:0] _handshake_unpack0_out0_data;	// ../tmp/unpack.mlir:7:14
  wire        _handshake_unpack0_out1_valid;	// ../tmp/unpack.mlir:7:14
  wire [31:0] _handshake_unpack0_out1_data;	// ../tmp/unpack.mlir:7:14
  wire        _handshake_unpack0_out2_valid;	// ../tmp/unpack.mlir:7:14
  wire [31:0] _handshake_unpack0_out2_data;	// ../tmp/unpack.mlir:7:14
  wire        _handshake_unpack0_out3_valid;	// ../tmp/unpack.mlir:7:14
  wire [31:0] _handshake_unpack0_out3_data;	// ../tmp/unpack.mlir:7:14
  wire        _handshake_unpack0_out4_valid;	// ../tmp/unpack.mlir:7:14
  wire [31:0] _handshake_unpack0_out4_data;	// ../tmp/unpack.mlir:7:14
  wire        _handshake_unpack0_out5_valid;	// ../tmp/unpack.mlir:7:14
  wire [31:0] _handshake_unpack0_out5_data;	// ../tmp/unpack.mlir:7:14
  wire        _handshake_unpack0_out6_valid;	// ../tmp/unpack.mlir:7:14
  wire [31:0] _handshake_unpack0_out6_data;	// ../tmp/unpack.mlir:7:14
  wire        _handshake_unpack0_out7_valid;	// ../tmp/unpack.mlir:7:14
  wire [31:0] _handshake_unpack0_out7_data;	// ../tmp/unpack.mlir:7:14
  wire        _handshake_unpack0_out8_valid;	// ../tmp/unpack.mlir:7:14
  wire [31:0] _handshake_unpack0_out8_data;	// ../tmp/unpack.mlir:7:14
  wire        _handshake_unpack0_out9_valid;	// ../tmp/unpack.mlir:7:14
  wire [31:0] _handshake_unpack0_out9_data;	// ../tmp/unpack.mlir:7:14
  wire        _handshake_unpack0_out10_valid;	// ../tmp/unpack.mlir:7:14
  wire [31:0] _handshake_unpack0_out10_data;	// ../tmp/unpack.mlir:7:14
  wire        _handshake_unpack0_out11_valid;	// ../tmp/unpack.mlir:7:14
  wire [31:0] _handshake_unpack0_out11_data;	// ../tmp/unpack.mlir:7:14
  wire        _handshake_unpack0_out12_valid;	// ../tmp/unpack.mlir:7:14
  wire [31:0] _handshake_unpack0_out12_data;	// ../tmp/unpack.mlir:7:14
  wire        _handshake_unpack0_out13_valid;	// ../tmp/unpack.mlir:7:14
  wire [31:0] _handshake_unpack0_out13_data;	// ../tmp/unpack.mlir:7:14
  wire        _handshake_unpack0_out14_valid;	// ../tmp/unpack.mlir:7:14
  wire [31:0] _handshake_unpack0_out14_data;	// ../tmp/unpack.mlir:7:14
  wire        _handshake_unpack0_out15_valid;	// ../tmp/unpack.mlir:7:14
  wire [31:0] _handshake_unpack0_out15_data;	// ../tmp/unpack.mlir:7:14

  handshake_unpack_in_tuple_ui32_ui32_ui32_ui32_ui32_ui32_ui32_ui32_ui32_ui32_ui32_ui32_ui32_ui32_ui32_ui32_out_ui32_ui32_ui32_ui32_ui32_ui32_ui32_ui32_ui32_ui32_ui32_ui32_ui32_ui32_ui32_ui32 handshake_unpack0 (	// ../tmp/unpack.mlir:7:14
    .in0_valid        (in0_valid),
    .in0_data_field0  (in0_data_field0),
    .in0_data_field1  (in0_data_field1),
    .in0_data_field2  (in0_data_field2),
    .in0_data_field3  (in0_data_field3),
    .in0_data_field4  (in0_data_field4),
    .in0_data_field5  (in0_data_field5),
    .in0_data_field6  (in0_data_field6),
    .in0_data_field7  (in0_data_field7),
    .in0_data_field8  (in0_data_field8),
    .in0_data_field9  (in0_data_field9),
    .in0_data_field10 (in0_data_field10),
    .in0_data_field11 (in0_data_field11),
    .in0_data_field12 (in0_data_field12),
    .in0_data_field13 (in0_data_field13),
    .in0_data_field14 (in0_data_field14),
    .in0_data_field15 (in0_data_field15),
    .out0_ready       (_arith_addi0_in0_ready),	// ../tmp/unpack.mlir:8:11
    .out1_ready       (_arith_addi0_in1_ready),	// ../tmp/unpack.mlir:8:11
    .out2_ready       (_arith_addi1_in0_ready),	// ../tmp/unpack.mlir:9:11
    .out3_ready       (_arith_addi1_in1_ready),	// ../tmp/unpack.mlir:9:11
    .out4_ready       (_arith_addi2_in0_ready),	// ../tmp/unpack.mlir:10:11
    .out5_ready       (_arith_addi2_in1_ready),	// ../tmp/unpack.mlir:10:11
    .out6_ready       (_arith_addi3_in0_ready),	// ../tmp/unpack.mlir:11:11
    .out7_ready       (_arith_addi3_in1_ready),	// ../tmp/unpack.mlir:11:11
    .out8_ready       (_arith_addi4_in0_ready),	// ../tmp/unpack.mlir:12:11
    .out9_ready       (_arith_addi4_in1_ready),	// ../tmp/unpack.mlir:12:11
    .out10_ready      (_arith_addi5_in0_ready),	// ../tmp/unpack.mlir:13:11
    .out11_ready      (_arith_addi5_in1_ready),	// ../tmp/unpack.mlir:13:11
    .out12_ready      (_arith_addi6_in0_ready),	// ../tmp/unpack.mlir:14:11
    .out13_ready      (_arith_addi6_in1_ready),	// ../tmp/unpack.mlir:14:11
    .out14_ready      (_arith_addi7_in0_ready),	// ../tmp/unpack.mlir:15:11
    .out15_ready      (_arith_addi7_in1_ready),	// ../tmp/unpack.mlir:15:11
    .clock            (clock),
    .reset            (reset),
    .in0_ready        (in0_ready),
    .out0_valid       (_handshake_unpack0_out0_valid),
    .out0_data        (_handshake_unpack0_out0_data),
    .out1_valid       (_handshake_unpack0_out1_valid),
    .out1_data        (_handshake_unpack0_out1_data),
    .out2_valid       (_handshake_unpack0_out2_valid),
    .out2_data        (_handshake_unpack0_out2_data),
    .out3_valid       (_handshake_unpack0_out3_valid),
    .out3_data        (_handshake_unpack0_out3_data),
    .out4_valid       (_handshake_unpack0_out4_valid),
    .out4_data        (_handshake_unpack0_out4_data),
    .out5_valid       (_handshake_unpack0_out5_valid),
    .out5_data        (_handshake_unpack0_out5_data),
    .out6_valid       (_handshake_unpack0_out6_valid),
    .out6_data        (_handshake_unpack0_out6_data),
    .out7_valid       (_handshake_unpack0_out7_valid),
    .out7_data        (_handshake_unpack0_out7_data),
    .out8_valid       (_handshake_unpack0_out8_valid),
    .out8_data        (_handshake_unpack0_out8_data),
    .out9_valid       (_handshake_unpack0_out9_valid),
    .out9_data        (_handshake_unpack0_out9_data),
    .out10_valid      (_handshake_unpack0_out10_valid),
    .out10_data       (_handshake_unpack0_out10_data),
    .out11_valid      (_handshake_unpack0_out11_valid),
    .out11_data       (_handshake_unpack0_out11_data),
    .out12_valid      (_handshake_unpack0_out12_valid),
    .out12_data       (_handshake_unpack0_out12_data),
    .out13_valid      (_handshake_unpack0_out13_valid),
    .out13_data       (_handshake_unpack0_out13_data),
    .out14_valid      (_handshake_unpack0_out14_valid),
    .out14_data       (_handshake_unpack0_out14_data),
    .out15_valid      (_handshake_unpack0_out15_valid),
    .out15_data       (_handshake_unpack0_out15_data)
  );
  arith_addi_in_ui32_ui32_out_ui32 arith_addi0 (	// ../tmp/unpack.mlir:8:11
    .in0_valid  (_handshake_unpack0_out0_valid),	// ../tmp/unpack.mlir:7:14
    .in0_data   (_handshake_unpack0_out0_data),	// ../tmp/unpack.mlir:7:14
    .in1_valid  (_handshake_unpack0_out1_valid),	// ../tmp/unpack.mlir:7:14
    .in1_data   (_handshake_unpack0_out1_data),	// ../tmp/unpack.mlir:7:14
    .out0_ready (_arith_addi8_in0_ready),	// ../tmp/unpack.mlir:17:11
    .in0_ready  (_arith_addi0_in0_ready),
    .in1_ready  (_arith_addi0_in1_ready),
    .out0_valid (_arith_addi0_out0_valid),
    .out0_data  (_arith_addi0_out0_data)
  );
  arith_addi_in_ui32_ui32_out_ui32 arith_addi1 (	// ../tmp/unpack.mlir:9:11
    .in0_valid  (_handshake_unpack0_out2_valid),	// ../tmp/unpack.mlir:7:14
    .in0_data   (_handshake_unpack0_out2_data),	// ../tmp/unpack.mlir:7:14
    .in1_valid  (_handshake_unpack0_out3_valid),	// ../tmp/unpack.mlir:7:14
    .in1_data   (_handshake_unpack0_out3_data),	// ../tmp/unpack.mlir:7:14
    .out0_ready (_arith_addi8_in1_ready),	// ../tmp/unpack.mlir:17:11
    .in0_ready  (_arith_addi1_in0_ready),
    .in1_ready  (_arith_addi1_in1_ready),
    .out0_valid (_arith_addi1_out0_valid),
    .out0_data  (_arith_addi1_out0_data)
  );
  arith_addi_in_ui32_ui32_out_ui32 arith_addi2 (	// ../tmp/unpack.mlir:10:11
    .in0_valid  (_handshake_unpack0_out4_valid),	// ../tmp/unpack.mlir:7:14
    .in0_data   (_handshake_unpack0_out4_data),	// ../tmp/unpack.mlir:7:14
    .in1_valid  (_handshake_unpack0_out5_valid),	// ../tmp/unpack.mlir:7:14
    .in1_data   (_handshake_unpack0_out5_data),	// ../tmp/unpack.mlir:7:14
    .out0_ready (_arith_addi9_in0_ready),	// ../tmp/unpack.mlir:18:11
    .in0_ready  (_arith_addi2_in0_ready),
    .in1_ready  (_arith_addi2_in1_ready),
    .out0_valid (_arith_addi2_out0_valid),
    .out0_data  (_arith_addi2_out0_data)
  );
  arith_addi_in_ui32_ui32_out_ui32 arith_addi3 (	// ../tmp/unpack.mlir:11:11
    .in0_valid  (_handshake_unpack0_out6_valid),	// ../tmp/unpack.mlir:7:14
    .in0_data   (_handshake_unpack0_out6_data),	// ../tmp/unpack.mlir:7:14
    .in1_valid  (_handshake_unpack0_out7_valid),	// ../tmp/unpack.mlir:7:14
    .in1_data   (_handshake_unpack0_out7_data),	// ../tmp/unpack.mlir:7:14
    .out0_ready (_arith_addi9_in1_ready),	// ../tmp/unpack.mlir:18:11
    .in0_ready  (_arith_addi3_in0_ready),
    .in1_ready  (_arith_addi3_in1_ready),
    .out0_valid (_arith_addi3_out0_valid),
    .out0_data  (_arith_addi3_out0_data)
  );
  arith_addi_in_ui32_ui32_out_ui32 arith_addi4 (	// ../tmp/unpack.mlir:12:11
    .in0_valid  (_handshake_unpack0_out8_valid),	// ../tmp/unpack.mlir:7:14
    .in0_data   (_handshake_unpack0_out8_data),	// ../tmp/unpack.mlir:7:14
    .in1_valid  (_handshake_unpack0_out9_valid),	// ../tmp/unpack.mlir:7:14
    .in1_data   (_handshake_unpack0_out9_data),	// ../tmp/unpack.mlir:7:14
    .out0_ready (_arith_addi10_in0_ready),	// ../tmp/unpack.mlir:19:11
    .in0_ready  (_arith_addi4_in0_ready),
    .in1_ready  (_arith_addi4_in1_ready),
    .out0_valid (_arith_addi4_out0_valid),
    .out0_data  (_arith_addi4_out0_data)
  );
  arith_addi_in_ui32_ui32_out_ui32 arith_addi5 (	// ../tmp/unpack.mlir:13:11
    .in0_valid  (_handshake_unpack0_out10_valid),	// ../tmp/unpack.mlir:7:14
    .in0_data   (_handshake_unpack0_out10_data),	// ../tmp/unpack.mlir:7:14
    .in1_valid  (_handshake_unpack0_out11_valid),	// ../tmp/unpack.mlir:7:14
    .in1_data   (_handshake_unpack0_out11_data),	// ../tmp/unpack.mlir:7:14
    .out0_ready (_arith_addi10_in1_ready),	// ../tmp/unpack.mlir:19:11
    .in0_ready  (_arith_addi5_in0_ready),
    .in1_ready  (_arith_addi5_in1_ready),
    .out0_valid (_arith_addi5_out0_valid),
    .out0_data  (_arith_addi5_out0_data)
  );
  arith_addi_in_ui32_ui32_out_ui32 arith_addi6 (	// ../tmp/unpack.mlir:14:11
    .in0_valid  (_handshake_unpack0_out12_valid),	// ../tmp/unpack.mlir:7:14
    .in0_data   (_handshake_unpack0_out12_data),	// ../tmp/unpack.mlir:7:14
    .in1_valid  (_handshake_unpack0_out13_valid),	// ../tmp/unpack.mlir:7:14
    .in1_data   (_handshake_unpack0_out13_data),	// ../tmp/unpack.mlir:7:14
    .out0_ready (_arith_addi11_in0_ready),	// ../tmp/unpack.mlir:20:11
    .in0_ready  (_arith_addi6_in0_ready),
    .in1_ready  (_arith_addi6_in1_ready),
    .out0_valid (_arith_addi6_out0_valid),
    .out0_data  (_arith_addi6_out0_data)
  );
  arith_addi_in_ui32_ui32_out_ui32 arith_addi7 (	// ../tmp/unpack.mlir:15:11
    .in0_valid  (_handshake_unpack0_out14_valid),	// ../tmp/unpack.mlir:7:14
    .in0_data   (_handshake_unpack0_out14_data),	// ../tmp/unpack.mlir:7:14
    .in1_valid  (_handshake_unpack0_out15_valid),	// ../tmp/unpack.mlir:7:14
    .in1_data   (_handshake_unpack0_out15_data),	// ../tmp/unpack.mlir:7:14
    .out0_ready (_arith_addi11_in1_ready),	// ../tmp/unpack.mlir:20:11
    .in0_ready  (_arith_addi7_in0_ready),
    .in1_ready  (_arith_addi7_in1_ready),
    .out0_valid (_arith_addi7_out0_valid),
    .out0_data  (_arith_addi7_out0_data)
  );
  arith_addi_in_ui32_ui32_out_ui32 arith_addi8 (	// ../tmp/unpack.mlir:17:11
    .in0_valid  (_arith_addi0_out0_valid),	// ../tmp/unpack.mlir:8:11
    .in0_data   (_arith_addi0_out0_data),	// ../tmp/unpack.mlir:8:11
    .in1_valid  (_arith_addi1_out0_valid),	// ../tmp/unpack.mlir:9:11
    .in1_data   (_arith_addi1_out0_data),	// ../tmp/unpack.mlir:9:11
    .out0_ready (_arith_addi12_in0_ready),	// ../tmp/unpack.mlir:22:11
    .in0_ready  (_arith_addi8_in0_ready),
    .in1_ready  (_arith_addi8_in1_ready),
    .out0_valid (_arith_addi8_out0_valid),
    .out0_data  (_arith_addi8_out0_data)
  );
  arith_addi_in_ui32_ui32_out_ui32 arith_addi9 (	// ../tmp/unpack.mlir:18:11
    .in0_valid  (_arith_addi2_out0_valid),	// ../tmp/unpack.mlir:10:11
    .in0_data   (_arith_addi2_out0_data),	// ../tmp/unpack.mlir:10:11
    .in1_valid  (_arith_addi3_out0_valid),	// ../tmp/unpack.mlir:11:11
    .in1_data   (_arith_addi3_out0_data),	// ../tmp/unpack.mlir:11:11
    .out0_ready (_arith_addi12_in1_ready),	// ../tmp/unpack.mlir:22:11
    .in0_ready  (_arith_addi9_in0_ready),
    .in1_ready  (_arith_addi9_in1_ready),
    .out0_valid (_arith_addi9_out0_valid),
    .out0_data  (_arith_addi9_out0_data)
  );
  arith_addi_in_ui32_ui32_out_ui32 arith_addi10 (	// ../tmp/unpack.mlir:19:11
    .in0_valid  (_arith_addi4_out0_valid),	// ../tmp/unpack.mlir:12:11
    .in0_data   (_arith_addi4_out0_data),	// ../tmp/unpack.mlir:12:11
    .in1_valid  (_arith_addi5_out0_valid),	// ../tmp/unpack.mlir:13:11
    .in1_data   (_arith_addi5_out0_data),	// ../tmp/unpack.mlir:13:11
    .out0_ready (_arith_addi13_in0_ready),	// ../tmp/unpack.mlir:23:11
    .in0_ready  (_arith_addi10_in0_ready),
    .in1_ready  (_arith_addi10_in1_ready),
    .out0_valid (_arith_addi10_out0_valid),
    .out0_data  (_arith_addi10_out0_data)
  );
  arith_addi_in_ui32_ui32_out_ui32 arith_addi11 (	// ../tmp/unpack.mlir:20:11
    .in0_valid  (_arith_addi6_out0_valid),	// ../tmp/unpack.mlir:14:11
    .in0_data   (_arith_addi6_out0_data),	// ../tmp/unpack.mlir:14:11
    .in1_valid  (_arith_addi7_out0_valid),	// ../tmp/unpack.mlir:15:11
    .in1_data   (_arith_addi7_out0_data),	// ../tmp/unpack.mlir:15:11
    .out0_ready (_arith_addi13_in1_ready),	// ../tmp/unpack.mlir:23:11
    .in0_ready  (_arith_addi11_in0_ready),
    .in1_ready  (_arith_addi11_in1_ready),
    .out0_valid (_arith_addi11_out0_valid),
    .out0_data  (_arith_addi11_out0_data)
  );
  arith_addi_in_ui32_ui32_out_ui32 arith_addi12 (	// ../tmp/unpack.mlir:22:11
    .in0_valid  (_arith_addi8_out0_valid),	// ../tmp/unpack.mlir:17:11
    .in0_data   (_arith_addi8_out0_data),	// ../tmp/unpack.mlir:17:11
    .in1_valid  (_arith_addi9_out0_valid),	// ../tmp/unpack.mlir:18:11
    .in1_data   (_arith_addi9_out0_data),	// ../tmp/unpack.mlir:18:11
    .out0_ready (_arith_addi14_in0_ready),	// ../tmp/unpack.mlir:25:12
    .in0_ready  (_arith_addi12_in0_ready),
    .in1_ready  (_arith_addi12_in1_ready),
    .out0_valid (_arith_addi12_out0_valid),
    .out0_data  (_arith_addi12_out0_data)
  );
  arith_addi_in_ui32_ui32_out_ui32 arith_addi13 (	// ../tmp/unpack.mlir:23:11
    .in0_valid  (_arith_addi10_out0_valid),	// ../tmp/unpack.mlir:19:11
    .in0_data   (_arith_addi10_out0_data),	// ../tmp/unpack.mlir:19:11
    .in1_valid  (_arith_addi11_out0_valid),	// ../tmp/unpack.mlir:20:11
    .in1_data   (_arith_addi11_out0_data),	// ../tmp/unpack.mlir:20:11
    .out0_ready (_arith_addi14_in1_ready),	// ../tmp/unpack.mlir:25:12
    .in0_ready  (_arith_addi13_in0_ready),
    .in1_ready  (_arith_addi13_in1_ready),
    .out0_valid (_arith_addi13_out0_valid),
    .out0_data  (_arith_addi13_out0_data)
  );
  arith_addi_in_ui32_ui32_out_ui32 arith_addi14 (	// ../tmp/unpack.mlir:25:12
    .in0_valid  (_arith_addi12_out0_valid),	// ../tmp/unpack.mlir:22:11
    .in0_data   (_arith_addi12_out0_data),	// ../tmp/unpack.mlir:22:11
    .in1_valid  (_arith_addi13_out0_valid),	// ../tmp/unpack.mlir:23:11
    .in1_data   (_arith_addi13_out0_data),	// ../tmp/unpack.mlir:23:11
    .out0_ready (out0_ready),
    .in0_ready  (_arith_addi14_in0_ready),
    .in1_ready  (_arith_addi14_in1_ready),
    .out0_valid (out0_valid),
    .out0_data  (out0_data)
  );
  assign inCtrl_ready = outCtrl_ready;
  assign outCtrl_valid = inCtrl_valid;
endmodule
