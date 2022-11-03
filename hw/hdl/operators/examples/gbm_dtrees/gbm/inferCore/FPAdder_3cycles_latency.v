//------------------------------------------------------------------------------
//                       FPAdder_8_23_uid2_RightShifter
//                      (RightShifter_24_by_max_26_uid4)
// This operator is part of the Infinite Virtual Library FloPoCoLib
// and is distributed under the terms of the GNU Lesser General Public Licence
// with a Tobin Tax restriction (see README file for details).
// Authors: Florent de Dinechin, Bogdan Pasca (2007,2008,2009,2010)
//------------------------------------------------------------------------------
// no timescale needed

module FPAdder_8_23_uid2_RightShifter_l3(
clk,
rst,
X,
S,
R
);

input clk, rst;
input [23:0] X;
input [4:0] S;
output [49:0] R;

wire clk;
wire rst;
wire [23:0] X;
wire [4:0] S;
wire [49:0] R;


wire [23:0] level0;
wire [4:0] ps;
wire [24:0] level1;
wire [26:0] level2;
wire [30:0] level3;
wire [38:0] level4;
wire [54:0] level5;


  assign level0 = X;
  assign ps = S;
  assign level1 = ps[0] == 1'b1 ? {1'b0,level0} : {level0,1'b0};
  assign level2 = ps[1] == 1'b1 ? {2'b00,level1} : {level1,2'b00};
  assign level3 = ps[2] == 1'b1 ? {4'b0000,level2} : {level2,4'b0000};
  assign level4 = ps[3] == 1'b1 ? {8'b00000000,level3} : {level3,8'b00000000};
  assign level5 = ps[4] == 1'b1 ? {16'b0000000000000000,level4} : {level4,16'b0000000000000000};
  assign R = level5[54:5];

endmodule

//------------------------------------------------------------------------------
//                           IntAdder_27_f150_uid6
// This operator is part of the Infinite Virtual Library FloPoCoLib
// and is distributed under the terms of the GNU Lesser General Public Licence
// with a Tobin Tax restriction (see README file for details).
// Authors: Bogdan Pasca, Florent de Dinechin (2008-2010)
//------------------------------------------------------------------------------
// Pipeline depth: 0 cycles
// no timescale needed

module IntAdder_27_f150_uid6_l3(
clk,
rst,
X,
Y,
Cin,
R
);

input clk, rst;
input [26:0] X;
input [26:0] Y;
input Cin;
output [26:0] R;

wire clk;
wire rst;
wire [26:0] X;
wire [26:0] Y;
wire Cin;
wire [26:0] R;


  //Alternative
  assign R = X + Y + Cin;

endmodule

//------------------------------------------------------------------------------
//                   LZCShifter_28_to_28_counting_32_uid16
// This operator is part of the Infinite Virtual Library FloPoCoLib
// and is distributed under the terms of the GNU Lesser General Public Licence
// with a Tobin Tax restriction (see README file for details).
// Authors: Florent de Dinechin, Bogdan Pasca (2007)
//------------------------------------------------------------------------------
// Pipeline depth: 1 cycles
// no timescale needed

module LZCShifter_28_to_28_counting_32_uid16_l3(
clk,
rst,
I,
Count,
O
);

input clk, rst;
input [27:0] I;
output [4:0] Count;
output [27:0] O;

wire clk;
wire rst;
wire [27:0] I;
wire [4:0] Count;
wire [27:0] O;
wire [27:0] level5;

wire count4; 
//reg count4_d1;
wire count4_d1;

wire [27:0] level4; 
//reg [27:0] level4_d1;
wire [27:0] level4_d1;

wire count3; 
//reg count3_d1;
wire count3_d1;

wire [27:0] level3;
wire count2;
wire [27:0] level2;
wire count1;
wire [27:0] level1;
wire count0;
wire [27:0] level0;
wire [4:0] sCount;

  assign level5 = I;
  assign count4 = level5[27:12] == 16'b0000000000000000 ? 1'b1 : 1'b0;
  assign level4 = count4 == 1'b0 ? level5[27:0] : {level5[11:0],16'b0000000000000000};
  assign count3 = level4[27:20] == 8'b00000000 ? 1'b1 : 1'b0;
  //--------------Synchro barrier, entering cycle 1----------------
  
  /* Added by Babis */
  assign count4_d1 = count4;
  assign level4_d1 = level4;
  assign count3_d1 = count3;

  assign level3 = count3_d1 == 1'b0 ? level4_d1[27:0] : {level4_d1[19:0],8'b00000000};
  assign count2 = level3[27:24] == 4'b0000 ? 1'b1 : 1'b0;
  assign level2 = count2 == 1'b0 ? level3[27:0] : {level3[23:0],4'b0000};
  assign count1 = level2[27:26] == 2'b00 ? 1'b1 : 1'b0;
  assign level1 = count1 == 1'b0 ? level2[27:0] : {level2[25:0],2'b00};
  assign count0 = level1[27:27] == 1'b0 ? 1'b1 : 1'b0;
  assign level0 = count0 == 1'b0 ? level1[27:0] : {level1[26:0],1'b0};
  assign O = level0;
  assign sCount = {count4_d1,count3_d1,count2,count1,count0};
  assign Count = sCount;

endmodule

//------------------------------------------------------------------------------
//                           IntAdder_34_f150_uid18
// This operator is part of the Infinite Virtual Library FloPoCoLib
// and is distributed under the terms of the GNU Lesser General Public Licence
// with a Tobin Tax restriction (see README file for details).
// Authors: Bogdan Pasca, Florent de Dinechin (2008-2010)
//------------------------------------------------------------------------------
// Pipeline depth: 0 cycles
// no timescale needed

module IntAdder_34_f150_uid18_l3(
clk,
rst,
X,
Y,
Cin,
R
);

input clk, rst;
input [33:0] X;
input [33:0] Y;
input Cin;
output [33:0] R;

wire clk;
wire rst;
wire [33:0] X;
wire [33:0] Y;
wire Cin;
wire [33:0] R;

  always @(posedge clk) begin
  end

  //Alternative
  assign R = X + Y + Cin;

endmodule

//------------------------------------------------------------------------------
//                             FPAdder_8_23_uid2
// This operator is part of the Infinite Virtual Library FloPoCoLib
// and is distributed under the terms of the GNU Lesser General Public Licence
// with a Tobin Tax restriction (see README file for details).
// Authors: Bogdan Pasca, Florent de Dinechin (2010)
//------------------------------------------------------------------------------
// Pipeline depth: 3 cycles
// no timescale needed

module FPAdder_8_23_uid2_l3(
clk,
rst,
seq_stall,
X,
Y,
R
);

input clk, rst, seq_stall;
input [8 + 23 + 2:0] X;
input [8 + 23 + 2:0] Y;
output [8 + 23 + 2:0] R;

wire clk;
wire rst;
wire seq_stall;
wire [8 + 23 + 2:0] X;
wire [8 + 23 + 2:0] Y;
wire [8 + 23 + 2:0] R;


wire [32:0] excExpFracX;
wire [32:0] excExpFracY;
wire [8:0] eXmeY;
wire [8:0] eYmeX;
wire swap;
wire [33:0] newX; reg [33:0] newX_d1;
wire [33:0] newY;
wire [7:0] expX; reg [7:0] expX_d1;
wire [1:0] excX;
wire [1:0] excY;
wire signX;
wire signY;
wire EffSub; reg EffSub_d1; reg EffSub_d2; reg EffSub_d3;
wire [5:0] sdsXsYExnXY;
wire [3:0] sdExnXY;
wire [23:0] fracY;
reg [1:0] excRt; reg [1:0] excRt_d1; reg [1:0] excRt_d2; reg [1:0] excRt_d3;
wire signR; reg signR_d1; reg signR_d2; reg signR_d3;
wire [8:0] expDiff;
wire shiftedOut;
wire [4:0] shiftVal;
wire [49:0] shiftedFracY; 

wire sticky;
wire [26:0] fracYfar;
wire [26:0] fracYfarXorOp;
wire [26:0] fracXfar;
wire cInAddFar;
wire [26:0] fracAddResult;
wire [27:0] fracGRS;

//added by Babis
reg [27:0] fracGRS_d1;

wire [9:0] extendedExpInc; reg [9:0] extendedExpInc_d1; reg [9:0] extendedExpInc_d2;
wire [4:0] nZerosNew; reg [4:0] nZerosNew_d1;
wire [27:0] shiftedFrac; 
reg [27:0] shiftedFrac_d1;

//reg [49:0] shiftedFracY_d1;

/* Added by Babis */
reg [4:0] shiftVal_d1;
reg [23:0] fracY_d1;

wire [9:0] updatedExp;
wire eqdiffsign;
wire [33:0] expFrac;
wire stk; reg stk_d1;
wire rnd; reg rnd_d1;
wire grd; reg grd_d1;
wire lsb; reg lsb_d1;
wire addToRoundBit;
wire [33:0] RoundedExpFrac;
wire [1:0] upExc;
wire [22:0] fracR;
wire [7:0] expR;
wire [3:0] exExpExc;
reg [1:0] excRt2;
wire [1:0] excR;
wire [33:0] computedR;

  always @(posedge clk) begin
    if(rst == 1'b1) begin
      newX_d1 <= {34{1'b0}};
      expX_d1 <= {8{1'b0}};
      EffSub_d1 <= 1'b 0;
      EffSub_d2 <= 1'b 0;
      EffSub_d3 <= 1'b 0;
      excRt_d1 <= {2{1'b0}};
      excRt_d2 <= {2{1'b0}};
      excRt_d3 <= {2{1'b0}};
      signR_d1 <= 1'b0;
      signR_d2 <= 1'b0;
      signR_d3 <= 1'b0;
      //shiftedFracY_d1 <= {50{1'b0}};
      /* Added by Babis */
      shiftVal_d1 <= {4{1'b0}};  
	   fracY_d1 <= {24{1'b0}};
      fracGRS_d1 <= {28{1'b0}}; 
      
	  extendedExpInc_d1 <= {10{1'b0}};
      extendedExpInc_d2 <= {10{1'b0}};
      nZerosNew_d1 <= {5{1'b0}};
      shiftedFrac_d1 <= {28{1'b0}};
      stk_d1 <= 1'b 0;
      rnd_d1 <= 1'b 0;
      grd_d1 <= 1'b 0;
      lsb_d1 <= 1'b 0;
    end
    else begin
      if(~seq_stall) begin
        newX_d1 <= newX;
        expX_d1 <= expX;
        EffSub_d1 <= EffSub;
        EffSub_d2 <= EffSub_d1;
        EffSub_d3 <= EffSub_d2;
        excRt_d1 <= excRt;
        excRt_d2 <= excRt_d1;
        excRt_d3 <= excRt_d2;
        signR_d1 <= signR;
        signR_d2 <= signR_d1;
        signR_d3 <= signR_d2;
        //shiftedFracY_d1 <= shiftedFracY;
       	/* Added by Babis */
        shiftVal_d1 <= shiftVal; 
		fracY_d1 <= fracY;      
        fracGRS_d1 <= fracGRS;
        
		extendedExpInc_d1 <= extendedExpInc;
        extendedExpInc_d2 <= extendedExpInc_d1;
        nZerosNew_d1 <= nZerosNew;
        shiftedFrac_d1 <= shiftedFrac;
        stk_d1 <= stk;
        rnd_d1 <= rnd;
        grd_d1 <= grd;
        lsb_d1 <= lsb;
      end
    end
  end

  // Exponent difference and swap  --
  assign excExpFracX = {X[33:32],X[30:0]};
  assign excExpFracY = {Y[33:32],Y[30:0]};
  assign eXmeY = ({1'b0,X[30:23]}) - ({1'b0,Y[30:23]});
  assign eYmeX = ({1'b0,Y[30:23]}) - ({1'b0,X[30:23]});
  assign swap = excExpFracX >= excExpFracY ? 1'b0 : 1'b1;
  assign newX = swap == 1'b0 ? X : Y;
  assign newY = swap == 1'b0 ? Y : X;
  assign expX = newX[30:23];
  assign excX = newX[33:32];
  assign excY = newY[33:32];
  assign signX = newX[31];
  assign signY = newY[31];
  assign EffSub = signX ^ signY;
  assign sdsXsYExnXY = {signX,signY,excX,excY};
  assign sdExnXY = {excX,excY};
  assign fracY = excY == 2'b00 ? 24'b000000000000000000000000 : {1'b1, newY[22:0]};
  always @(*) begin
    case(sdsXsYExnXY)
      6'b000000,6'b010000,6'b100000,6'b110000 : excRt <= 2'b00;
      6'b000101,6'b010101,6'b100101,6'b110101,6'b000100,6'b010100,6'b100100,6'b110100,6'b000001,6'b010001,6'b100001,6'b110001 : excRt <= 2'b01;
      6'b111010,6'b001010,6'b001000,6'b011000,6'b101000,6'b111000,6'b000010,6'b010010,6'b100010,6'b110010,6'b001001,6'b011001,6'b101001,6'b111001,6'b000110,6'b010110,6'b100110,6'b110110 : excRt <= 2'b10;
      default : excRt <= 2'b11;
    endcase
  end

  assign signR = (sdsXsYExnXY == 6'b100000 || sdsXsYExnXY == 6'b010000) ? 1'b0 : signX;
  //-------------- cycle 0----------------
  assign expDiff = swap == 1'b0 ? eXmeY : eYmeX;
  assign shiftedOut = (expDiff >= 25) ? 1'b1 : 1'b0;
  assign shiftVal = shiftedOut == 1'b0 ? expDiff[4:0] : 5'b11010;
  FPAdder_8_23_uid2_RightShifter_l3 RightShifterComponent(
      .clk(clk),
    .rst(rst),
    .R(shiftedFracY),
    .S(shiftVal_d1),
    .X(fracY_d1));

  //--------------Synchro barrier, entering cycle 1----------------
  assign sticky = (shiftedFracY[23:0] == 23'b00000000000000000000000) ? 1'b0 : 1'b1;
  //-------------- cycle 0----------------
  //--------------Synchro barrier, entering cycle 1----------------
  assign fracYfar = {1'b0,shiftedFracY[49:24]};
  assign fracYfarXorOp = fracYfar ^ ({EffSub_d1,EffSub_d1,EffSub_d1,EffSub_d1,EffSub_d1,EffSub_d1,EffSub_d1,EffSub_d1,EffSub_d1,EffSub_d1,EffSub_d1,EffSub_d1,EffSub_d1,EffSub_d1,EffSub_d1,EffSub_d1,EffSub_d1,EffSub_d1,EffSub_d1,EffSub_d1,EffSub_d1,EffSub_d1,EffSub_d1,EffSub_d1,EffSub_d1,EffSub_d1,EffSub_d1});
  assign fracXfar = {2'b01,(newX_d1[22:0]),2'b00};
  assign cInAddFar = EffSub_d1 &  ~sticky;
  IntAdder_27_f150_uid6_l3 fracAdder(
      .clk(clk),
    .rst(rst),
    .Cin(cInAddFar),
    .R(fracAddResult),
    .X(fracXfar),
    .Y(fracYfarXorOp));

  assign fracGRS = {fracAddResult,sticky};
  assign extendedExpInc = ({2'b 00,expX_d1}) + 1'b 1;
  LZCShifter_28_to_28_counting_32_uid16_l3 LZC_component(
      .clk(clk),
    .rst(rst),
    .Count(nZerosNew),
    .I(fracGRS_d1), /* Added by Babis */
    .O(shiftedFrac));

  //--------------Synchro barrier, entering cycle 2----------------
  //--------------Synchro barrier, entering cycle 3----------------
  assign updatedExp = extendedExpInc_d2 - ({5'b00000,nZerosNew_d1});
  assign eqdiffsign = nZerosNew_d1 == 5'b11111 ? 1'b1 : 1'b0;
  assign expFrac = {updatedExp,shiftedFrac_d1[26:3]};
  //-------------- cycle 2----------------
  assign stk = shiftedFrac[1] | shiftedFrac[0];
  assign rnd = shiftedFrac[2];
  assign grd = shiftedFrac[3];
  assign lsb = shiftedFrac[4];
  //--------------Synchro barrier, entering cycle 3----------------
  assign addToRoundBit = (lsb_d1 == 1'b 0 && grd_d1 == 1'b 1 && rnd_d1 == 1'b 0 && stk_d1 == 1'b 0) ? 1'b 0 : 1'b 1;
  IntAdder_34_f150_uid18_l3 roundingAdder(
      .clk(clk),
    .rst(rst),
    .Cin(addToRoundBit),
    .R(RoundedExpFrac),
    .X(expFrac),
    .Y(34'b0000000000000000000000000000000000));

  //-------------- cycle 3----------------
  assign upExc = RoundedExpFrac[33:32];
  assign fracR = RoundedExpFrac[23:1];
  assign expR = RoundedExpFrac[31:24];
  assign exExpExc = {upExc,excRt_d3};
  always @(*) begin
    case((exExpExc))
      4'b 0000,4'b 0100,4'b 1000,4'b 1100,4'b 1001,4'b 1101 : excRt2 <= 2'b 00;
      4'b 0001 : excRt2 <= 2'b 01;
      4'b 0010,4'b 0110,4'b 0101 : excRt2 <= 2'b 10;
      default : excRt2 <= 2'b 11;
    endcase
  end

  assign excR = (eqdiffsign == 1'b 1 && EffSub_d3 == 1'b 1) ? 2'b 00 : excRt2;
  assign computedR = {excR,signR_d3,expR,fracR};
  assign R = computedR;

endmodule
