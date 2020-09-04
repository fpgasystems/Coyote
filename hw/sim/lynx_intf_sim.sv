package lynxSimTypes;
    
    import lynxTypes::*;

    //
    // Request driver
    //
    class REQdrv;

        // Interface handle;
        virtual reqIntf req;

        // ID
        integer id;

        // Constructor
        function new(virtual reqIntf req, input integer id);
            this.req = req;
            this.id = id;
        endfunction

        // Cycle wait
        task cycle_wait;
            @(posedge req.aclk);
        endtask
        
        task cycle_n_wait(input integer n_cyc);
            for(int i = 0; i < n_cyc; i++) cycle_wait();
        endtask

        // Reset
        task reset_m;
            req.valid <= 1'b0;
            req.req <= 0;
        endtask
        
        task reset_s;
            req.ready <= 1'b0;
        endtask

        // Drive
        task send (
            input logic [63:0] len,
            input logic [47:0] vaddr,
            input logic sync,
            input logic ctl,
            input logic stream,
            input integer n_tr
        );
            req.req.len <= len;
            req.req.vaddr <= vaddr;
            req.req.sync <= sync;
            req.req.ctl <= ctl;
            req.req.stream <= stream;
            req.req.rsrvd = 0;
            req.valid <= 1'b1;
            for(int i = 0; i < n_tr; i++) begin
                cycle_wait();
                while(req.ready != 1'b1) begin cycle_wait(); end
            end
            req.valid <= 1'b0;
            req.req = 0;
            //$display("REQ: Request sent %d", id);
        endtask

        task recv (
            input integer n_tr
        );
            req.ready <= 1'b1;
            for(int i = 0; i < n_tr; i++) begin
                cycle_wait();
                while(req.valid != 1'b1) begin cycle_wait(); end
            end
            req.ready <= 1'b0;
            //$display("REQ: Request received %d", id);
        endtask

    endclass

    //
    // Meta driver
    //
    class METAdrv #(
        parameter integer DB = 128
    );

        // Interface handle;
        virtual metaIntf #(.DATA_BITS(DB)) meta;
        
        // ID
        integer id;

        // Constructor
        function new(virtual metaIntf #(.DATA_BITS(DB)) meta, input integer id);
            this.meta = meta;
            this.id = id;
        endfunction

        // Cycle wait
        task cycle_wait;
            @(posedge meta.aclk);
        endtask
        
        task cycle_n_wait(input integer n_cyc);
            for(int i = 0; i < n_cyc; i++) cycle_wait();
        endtask

        // Reset
        task reset_m;
            meta.valid <= 1'b0;
            meta.data <= 0;
        endtask

        task reset_s;
            meta.ready <= 1'b0;
        endtask

        // Drive
        task send (
            input logic [DB-1:0] data,
            input integer n_tr
        );
            meta.data <= data;
            meta.valid <= 1'b1;
            for(int i = 0; i < n_tr; i++) begin
                cycle_wait();
                while(meta.ready != 1'b1) begin cycle_wait(); end
            end
            meta.valid <= 1'b0;
            //$display("META: Request sent %d", id);
        endtask

        task recv (
            input integer n_tr
        );
            meta.ready <= 1'b1;
            for(int i = 0; i < n_tr; i++) begin
                cycle_wait();
                while(meta.valid != 1'b1) begin cycle_wait(); end 
            end  
            meta.ready <= 1'b0;
            //$display("META: Request received %d", id);
        endtask

    endclass

    //
    // DMA drivers
    //
    class DMAdrv;

        // Interface handle;
        virtual dmaIntf req;

        // ID
        integer id;

        // Constructor
        function new(virtual dmaIntf req, input integer id);
            this.req = req;
            this.id = id;
        endfunction

        // Cycle wait
        task cycle_wait;
            @(posedge req.aclk);
        endtask
        
        task cycle_n_wait(input integer n_cyc);
            for(int i = 0; i < n_cyc; i++) cycle_wait();
        endtask

        // Reset
        task reset_m;
            req.valid <= 1'b0;
            req.req <= 0;
        endtask

        task reset_s;
            req.ready <= 1'b0;
            req.done <= 0;
        endtask

        // Recv request
        task recv_dma (
            output logic [PADDR_BITS-1:0] paddr,
            output logic [LEN_BITS-1:0] len,
            output logic ctl
        );
            req.ready <= 1'b1;
            cycle_wait();
            while(req.valid != 1'b1) begin cycle_wait(); end
            paddr = req.req.paddr;
            len = req.req.len;
            ctl = req.req.ctl;
            cycle_wait();
            req.ready <= 1'b0;
        endtask

        // Send request
        task send_dma (
            input logic [PADDR_BITS-1:0] paddr,
            input logic [LEN_BITS-1:0] len,
            input logic ctl  
        );
            req.req.paddr <= paddr;
            req.req.len <= len;
            req.req.ctl <= ctl;
            req.valid <= 1'b1;
            cycle_wait();
            while(req.ready != 1'b1) begin cycle_wait(); end
            req.req.paddr <= 0;
            req.req.len <= 0;
            req.req.ctl <= 0;
            req.valid <= 1'b0;
        endtask

        // Send done
        task send_done ();
            req.done <= 1'b1;
            cycle_wait();
            req.done <= 1'b0;
        endtask

    endclass

endpackage