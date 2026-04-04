module ring_oscillator(
    input wire signal_in, 
    output wire signal_out
); 

    // Definition of intermediate wires 
    wire w1, w2, w3; 

    // Inverter chain to create oscillation
    (* DONT_TOUCH = "TRUE" *)
    LUT1 #(.INIT(2'b01)) inv1 (
        .I0(w3), 
        .O(w1)
    ); 

    (* DONT_TOUCH = "TRUE" *)
    LUT1 #(.INIT(2'b01)) inv2 (
        .I0(w1),
        .O(w2)
    );

    (* DONT_TOUCH = "TRUE" *)
    LUT2 #(.INIT(4'h7)) nand_gate (
        .I0(w2),
        .I1(signal_in),
        .O(w3)
    ); 

    // Final output assignment
    assign signal_out = w3; 

endmodule 