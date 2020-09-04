#########################################################################################
# Package
#########################################################################################
proc wr_hdl_pkg {f_out} {	
	upvar #0 cfg cnfg

	set template {}
	set entity {}
    if {$cnfg(en_strm) eq 1} {
		append entity "`define EN_STRM\n"
	}
    if {$cnfg(en_ddr) eq 1} {
		append entity "`define EN_DDR\n"
	}
    if {$cnfg(en_pr) eq 1} {
		append entity "`define EN_PR\n"
	}
    if {$cnfg(en_bpss) eq 1} {
		append entity "`define EN_BPSS\n"
	}
	if {$cnfg(en_avx) eq 1} {
		append entity "`define EN_AVX\n"
	}
	if {$cnfg(en_fv) eq 1} {
		append entity "`define EN_FV\n"
	}
	if {$cnfg(en_fvv) eq 1} {
		append entity "`define EN_FVV\n"
	}
	if {$cnfg(n_reg) > 1} {
		append entity "`define MULT_REGIONS\n"
	}
	append entity "\n"
	append entity "package lynxTypes;\n"
	append entity "\n"
	append entity "	// AXI\n"
	append entity "	parameter integer AXIL_DATA_BITS = 64;\n"
	append entity "	parameter integer AVX_DATA_BITS = 256;\n"
	append entity "	parameter integer AXI_DATA_BITS = 512;\n"
	append entity "	parameter integer AXI_ADDR_BITS = 64;\n"
	append entity "\n"
	append entity "	// TLB ram\n"
	append entity "	parameter integer TLB_S_ORDER = 10;\n"
	append entity "	parameter integer PG_S_BITS = 12;\n"
	append entity "	parameter integer N_S_ASSOC = 4;\n"
	append entity "\n"
	append entity "	parameter integer TLB_L_ORDER = 6;\n"
	append entity "	parameter integer PG_L_BITS = 21;\n"
	append entity "	parameter integer N_L_ASSOC = 2;\n"
	append entity "\n"
	append entity "	// Data\n"
	append entity "	parameter integer ADDR_BITS = 64;\n"
	append entity "	parameter integer PADDR_BITS = 40;\n"
	append entity "	parameter integer VADDR_BITS = 48;\n"
	append entity "	parameter integer LEN_BITS = 28;\n"
	append entity "	parameter integer TLB_DATA_BITS = 64;\n"
	append entity "\n"
	append entity "	// Queue depth\n"
	append entity "	parameter integer QUEUE_DEPTH = 8;\n"
	append entity "	parameter integer N_OUTSTANDING = 8;\n"
	append entity "\n"
	append entity " // Slices\n"
	append entity "	parameter integer N_REG_HOST_S0 = 2;\n"
	append entity "	parameter integer N_REG_HOST_S1 = 2;\n"
	append entity "	parameter integer N_REG_HOST_S2 = 2;\n"
	append entity "	parameter integer N_REG_CARD_S0 = 2;\n"
	append entity "	parameter integer N_REG_CARD_S1 = 2;\n"
	append entity "	parameter integer N_REG_CARD_S2 = 2;\n"
	append entity "\n"
	append entity " // Network\n"
	append entity "	parameter integer FV_REQ_BITS = 256;\n"
	append entity "	parameter integer PMTU_BITS = 1408;\n"
	append entity "\n"
	append entity " // -----------------------------------------------------------------\n"
	append entity " // Dynamic\n"
	append entity " // -----------------------------------------------------------------\n"
	append entity "\n"
	append entity " // Flow\n"
	append entity "	parameter integer N_DDR_CHAN = $cnfg(n_ddr_chan);\n"
	append entity "	parameter integer N_CHAN = $cnfg(n_chan); \n"
	append entity "	parameter integer N_REGIONS = $cnfg(n_reg);\n"
	append entity "	parameter integer PR_FLOW = $cnfg(en_pr);\n"
	append entity "	parameter integer AVX_FLOW = $cnfg(en_avx);\n"
	append entity "	parameter integer BPSS_FLOW = $cnfg(en_bpss);\n"
	append entity "	parameter integer DDR_FLOW = $cnfg(en_ddr);\n"
	append entity "	parameter integer FV_FLOW = $cnfg(en_fv);\n"
	append entity "	parameter integer FV_VERBS = $cnfg(en_fvv);\n"
	if {$cnfg(n_reg) == 1} {
		set nn 2
	} else {
		set nn $cnfg(n_reg)
	}
	append entity "	parameter integer N_REGIONS_BITS = \$clog2($nn);\n"
	append entity "	parameter integer N_REQUEST_BITS = 4;\n"
	append entity "\n"
	append entity "// ----------------------------------------------------------------------------\n"
    append entity "// -- Structs\n"
    append entity "// ----------------------------------------------------------------------------\n"
    append entity "typedef struct packed {\n"
    append entity "    logic \[VADDR_BITS-1:0] vaddr;\n"
    append entity "    logic \[LEN_BITS-1:0] len;\n"
    append entity "    logic stream;\n"
    append entity "    logic sync;\n"
    append entity "    logic ctl;\n"
	append entity "    logic \[3:0] dest;\n"
    append entity "    logic \[12:0] rsrvd;\n"
    append entity "} req_t;\n"
    append entity "\n"
	append entity "typedef struct packed {\n"
    append entity "    logic \[VADDR_BITS-1:0] vaddr;\n"
    append entity "    logic \[LEN_BITS-1:0] len;\n"
    append entity "    logic stream;\n"
    append entity "    logic sync;\n"
    append entity "    logic ctl;\n"
	append entity "    logic \[3:0] dest;\n"
	append entity "    logic \[N_REQUEST_BITS-1:0] id;\n"
	append entity "    logic host;\n"
    append entity "    logic \[7:0] rsrvd;\n"
    append entity "} rdma_req_t;\n"
    append entity "\n"
    append entity "typedef struct packed {\n"
    append entity "    logic \[PADDR_BITS-1:0] paddr;\n"
    append entity "    logic \[LEN_BITS-1:0] len;\n"
    append entity "    logic ctl;\n"
	append entity "    logic \[3:0] dest;\n"
	append entity "    logic \[22:0] rsrvd;\n"
    append entity "} dma_req_t;\n"
    append entity "\n"
    append entity "typedef struct packed {\n"
    append entity "    logic \[PADDR_BITS-1:0] paddr_card;\n"
    append entity "    logic \[PADDR_BITS-1:0] paddr_host;\n"
    append entity "    logic \[LEN_BITS-1:0] len;\n"
    append entity "    logic ctl;\n"
	append entity "    logic \[3:0] dest;\n"
    append entity "    logic isr;\n"
	append entity "    logic \[13:0] rsrvd;\n"
    append entity "} dma_isr_req_t;\n"
    append entity "\n"
    append entity "typedef struct packed {\n"
    append entity "    logic miss;\n"
    append entity "    logic \[VADDR_BITS-1:0] vaddr;\n"
    append entity "    logic \[LEN_BITS-1:0] len;\n"
    append entity "} pf_t;\n"
    append entity "\n"
    append entity "typedef struct packed {\n"
    append entity "    logic \[N_REGIONS_BITS-1:0] id;\n"
    append entity "    logic \[LEN_BITS-1:0] len;\n"
    append entity "} mux_t;\n"
	append entity "\n"
	append entity "endpackage\n"
	lappend template $entity
	set vho_file [open $f_out w]
	foreach line $template {
		puts $vho_file $line
	}
	close $vho_file
}