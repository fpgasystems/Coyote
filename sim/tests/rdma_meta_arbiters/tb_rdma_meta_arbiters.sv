`timescale 1ns / 1ps
// Test bench for the RDMA arbiters with several vFPGAs (MULT_REGIONS): rdma_meta_tx_arbiter takes a
// WRITE request and its payload beat from each vFPGA, rdma_meta_rx_arbiter hands an
// acknowledgement to each vFPGA. Every request, beat and acknowledgement must arrive, with the
// interfaces' assertions active throughout. See run.sh.
import lynxTypes::*;

module tb;
    logic aclk = 0;
    logic aresetn = 0;
    always #2 aclk = ~aclk;

    metaIntf #(.STYPE(dreq_t)) tx_in [N_REGIONS] (.aclk(aclk), .aresetn(aresetn));
    metaIntf #(.STYPE(dreq_t)) tx_out (.aclk(aclk), .aresetn(aresetn));
    AXI4S #(.AXI4S_DATA_BITS(AXI_NET_BITS)) rd_in [N_REGIONS] (.aclk(aclk), .aresetn(aresetn));
    AXI4S #(.AXI4S_DATA_BITS(AXI_NET_BITS)) rd_out (.aclk(aclk), .aresetn(aresetn));
    logic [N_REGIONS_BITS-1:0] tx_vfid;

    metaIntf #(.STYPE(ack_t)) rx_in (.aclk(aclk), .aresetn(aresetn));
    metaIntf #(.STYPE(ack_t)) rx_user [N_REGIONS] (.aclk(aclk), .aresetn(aresetn));
    metaIntf #(.STYPE(ack_t)) rx_host (.aclk(aclk), .aresetn(aresetn));
    logic [N_REGIONS_BITS-1:0] rx_vfid;

    rdma_meta_tx_arbiter inst_tx (.aclk(aclk), .aresetn(aresetn), .s_meta(tx_in), .m_meta(tx_out),
                                  .s_axis_rd(rd_in), .m_axis_rd(rd_out), .vfid(tx_vfid));
    rdma_meta_rx_arbiter inst_rx (.aclk(aclk), .aresetn(aresetn), .s_meta(rx_in), .m_meta_user(rx_user),
                                  .m_meta_host(rx_host), .vfid(rx_vfid));

    int tx_reqs = 0, tx_beats = 0, rx_acks [N_REGIONS];
    logic [N_REGIONS-1:0] beat_seen = '0;

    // Each vFPGA offers one WRITE request of one beat, and the beat, tagged with its index
    for (genvar i = 0; i < N_REGIONS; i++) begin : region
        initial begin
            dreq_t r = '0;
            r.req_1.opcode = RC_RDMA_WRITE_ONLY;
            r.req_1.len = AXI_NET_BITS / 8;
            r.req_1.last = 1'b1;
            tx_in[i].valid = 1'b0;
            tx_in[i].data = r;
            rd_in[i].tvalid = 1'b0;
            rd_in[i].tdata = AXI_NET_BITS'(i + 1);
            rd_in[i].tkeep = '1;
            rd_in[i].tlast = 1'b1;
            wait (aresetn);
            @(posedge aclk);
            tx_in[i].valid <= 1'b1;
            rd_in[i].tvalid <= 1'b1;
            fork
                begin do @(posedge aclk); while (!tx_in[i].ready); tx_in[i].valid <= 1'b0; end
                begin do @(posedge aclk); while (!rd_in[i].tready); rd_in[i].tvalid <= 1'b0; end
            join
        end

        assign rx_user[i].ready = 1'b1;
        initial rx_acks[i] = 0;
        always @(posedge aclk) if (aresetn && rx_user[i].valid && rx_user[i].ready) begin
            if (rx_user[i].data.vfid != i) $display("TB FAIL: vFPGA %0d got an acknowledgement for %0d", i, rx_user[i].data.vfid);
            rx_acks[i]++;
        end
    end

    assign tx_out.ready = 1'b1;
    assign rd_out.tready = 1'b1;
    assign rx_host.ready = 1'b1;
    always @(posedge aclk) if (aresetn) begin
        if (tx_out.valid && tx_out.ready) tx_reqs++;
        if (rd_out.tvalid && rd_out.tready) begin
            tx_beats++;
            if (rd_out.tdata >= 1 && rd_out.tdata <= N_REGIONS) beat_seen[rd_out.tdata - 1] = 1'b1;
        end
    end

    // One acknowledgement for each vFPGA
    initial begin
        ack_t a = '0;
        rx_in.valid = 1'b0;
        rx_in.data = '0;
        wait (aresetn);
        for (int i = 0; i < N_REGIONS; i++) begin
            a.vfid = i;
            a.opcode = RC_ACK;
            @(posedge aclk);
            rx_in.valid <= 1'b1;
            rx_in.data <= a;
            do @(posedge aclk); while (!rx_in.ready);
            rx_in.valid <= 1'b0;
        end
    end

    initial begin
        bit ok;
        repeat (10) @(posedge aclk);
        aresetn <= 1'b1;
        repeat (200) @(posedge aclk);
        ok = tx_reqs == N_REGIONS && tx_beats == N_REGIONS && beat_seen == '1;
        for (int i = 0; i < N_REGIONS; i++) ok &= rx_acks[i] == 1;
        $display("TB %0d vFPGAs: %0d requests and %0d payload beats sent, acknowledgements received %p",
                 N_REGIONS, tx_reqs, tx_beats, rx_acks);
        if (ok) $display("TB PASS");
        else $display("TB FAILED");
        $finish;
    end
endmodule
