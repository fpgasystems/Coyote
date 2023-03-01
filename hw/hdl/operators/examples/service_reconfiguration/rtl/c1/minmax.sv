import lynxTypes::*;

module minmax (
    input  logic                aclk,
    input  logic                aresetn,

    AXI4SR.s                    axis_in,

    input  logic                clr,
    output logic                done,

    output logic [31:0]         min,
    output logic [31:0]         max
);

localparam integer N_INTS = AXI_DATA_BITS / 32;

logic [1:0][4:0][15:0][31:0] data_C;
logic [4:0] val_C;
logic [4:0] last_C;
logic [31:0] min_C;
logic [31:0] max_C;

always_ff @( posedge aclk ) begin : REG
    if(~aresetn) begin
        data_C <= 'X;
        val_C <= 0;
        last_C <= 'X;
        min_C <= 32'h7fffffff;
        max_C <= 32'h00000000;
        done <= 1'b0;
    end
    else begin
        if(clr) begin
            min_C <= 32'h7fffffff;
            max_C <= 32'h00000000;
        end

        // Prop
        val_C[0] <= axis_in.tvalid;
        last_C[0] <= axis_in.tlast;

        val_C[1] <= val_C[0];
        last_C[1] <= last_C[0];

        val_C[2] <= val_C[1];
        last_C[2] <= last_C[1];

        val_C[3] <= val_C[2];
        last_C[3] <= last_C[2];

        val_C[4] <= val_C[3];
        last_C[4] <= last_C[3];

        done <= val_C[4] && last_C[4];

        // Min
        data_C[0][0] <= axis_in.tdata;
        
        for(int i = 0; i < 8; i++)
            data_C[0][1][i] <= data_C[0][0][i] < data_C[0][0][i+8] ? data_C[0][0][i] : data_C[0][0][i+8];
        

        for(int i = 0; i < 4; i++)
            data_C[0][2][i] <= data_C[0][1][i] < data_C[0][1][i+4] ? data_C[0][1][i] : data_C[0][1][i+4];
        

        for(int i = 0; i < 2; i++)
            data_C[0][3][i] <= data_C[0][2][i] < data_C[0][2][i+2] ? data_C[0][2][i] : data_C[0][2][i+2];
        

        data_C[0][4][0] <= data_C[0][3][0] < data_C[0][3][1] ? data_C[0][3][0] : data_C[0][3][1];
        

        min_C <= (data_C[0][4][0] < min_C) && val_C[4] ? data_C[0][4][0] : min_C;

        // Max
        data_C[1][0] <= axis_in.tdata;
        
        for(int i = 0; i < 8; i++)
            data_C[1][1][i] <= data_C[1][0][i] > data_C[1][0][i+8] ? data_C[1][0][i] : data_C[1][0][i+8];

        for(int i = 0; i < 4; i++)
            data_C[1][2][i] <= data_C[1][1][i] > data_C[1][1][i+4] ? data_C[1][1][i] : data_C[1][1][i+4];

        for(int i = 0; i < 2; i++)
            data_C[1][3][i] <= data_C[1][2][i] > data_C[1][2][i+2] ? data_C[1][2][i] : data_C[1][2][i+2];

        data_C[1][4][0] <= data_C[1][3][0] > data_C[1][3][1] ? data_C[1][3][0] : data_C[1][3][1];

        max_C <= (data_C[1][4][0] > max_C) && val_C[4] ? data_C[1][4][0] : max_C;

    end
end

assign axis_in.tready = 1'b1;

assign min = min_C;
assign max = max_C;

endmodule