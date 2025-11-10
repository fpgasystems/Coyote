#PCIe

#Clock
set_property	PACKAGE_PIN	AF8	            [get_ports 	{pcie_clk_clk_n}] ; #(for x16 or x8 bifurcated lanes 8-16)
set_property	PACKAGE_PIN	AF9             [get_ports 	{pcie_clk_clk_p}] ; #(for x16 or x8 bifurcated lanes 8-16)
#set_property	PACKAGE_PIN	AB8	            [get_ports 	{pcie_clk_clk_n}] ; #(for x8 bifurcated lanes 0-7)
#set_property	PACKAGE_PIN	AB9             [get_ports 	{pcie_clk_clk_p}] ; #(for x8 bifurcated lanes 0-7)

create_clock -period 10.000 -name pcie_ref_clk         [get_ports pcie_clk_clk_p]

set_property	PACKAGE_PIN	AW27		    [get_ports 	perst_n_nb	] ; 
set_property	IOSTANDARD		LVCMOS18	[get_ports 	perst_n_nb	] ; 

# Set false path
set_false_path -from [get_ports perst_n_nb]

# Transceiver
set_property	PACKAGE_PIN	BE5 	        [get_ports 	{pcie_x16_rxn[15]}	] ; 
set_property	PACKAGE_PIN	BD3 	        [get_ports 	{pcie_x16_rxn[14]}	] ; 
set_property	PACKAGE_PIN	BB3 	        [get_ports 	{pcie_x16_rxn[13]}	] ; 
set_property	PACKAGE_PIN	AY3 	        [get_ports 	{pcie_x16_rxn[12]}	] ; 
set_property	PACKAGE_PIN	BE6 	        [get_ports 	{pcie_x16_rxp[15]}	] ; 
set_property	PACKAGE_PIN	BD4 	        [get_ports 	{pcie_x16_rxp[14]}	] ; 
set_property	PACKAGE_PIN	BB4 	        [get_ports 	{pcie_x16_rxp[13]}	] ; 
set_property	PACKAGE_PIN	AY4 	        [get_ports 	{pcie_x16_rxp[12]}	] ; 
set_property	PACKAGE_PIN	AT8 	        [get_ports 	{pcie_x16_txn[15]}	] ; 
set_property	PACKAGE_PIN	AR6	            [get_ports 	{pcie_x16_txn[14]}	] ; 
set_property	PACKAGE_PIN	AP8 	        [get_ports 	{pcie_x16_txn[13]}	] ; 
set_property	PACKAGE_PIN	AN6	            [get_ports 	{pcie_x16_txn[12]}	] ; 
set_property	PACKAGE_PIN	AT9 	        [get_ports 	{pcie_x16_txp[15]}	] ; 
set_property	PACKAGE_PIN	AR7	            [get_ports 	{pcie_x16_txp[14]}	] ; 
set_property	PACKAGE_PIN	AP9 	        [get_ports 	{pcie_x16_txp[13]}	] ; 
set_property	PACKAGE_PIN	AN7	            [get_ports 	{pcie_x16_txp[12]}	] ; 
set_property	PACKAGE_PIN	BC1 	        [get_ports 	{pcie_x16_rxn[11]}	] ; 
set_property	PACKAGE_PIN	BA1 	        [get_ports 	{pcie_x16_rxn[10]}	] ; 
set_property	PACKAGE_PIN	AW1 	        [get_ports 	{pcie_x16_rxn[9]}	] ; 
set_property	PACKAGE_PIN	AV3 	        [get_ports 	{pcie_x16_rxn[8]}	] ; 
set_property	PACKAGE_PIN	BC2 	        [get_ports 	{pcie_x16_rxp[11]}	] ; 
set_property	PACKAGE_PIN	BA2 	        [get_ports 	{pcie_x16_rxp[10]}	] ; 
set_property	PACKAGE_PIN	AW2 	        [get_ports 	{pcie_x16_rxp[9]}	] ; 
set_property	PACKAGE_PIN	AV4 	        [get_ports 	{pcie_x16_rxp[8]}	] ; 
set_property	PACKAGE_PIN	AM8 	        [get_ports 	{pcie_x16_txn[11]}	] ; 
set_property	PACKAGE_PIN	AL6	            [get_ports 	{pcie_x16_txn[10]}	] ; 
set_property	PACKAGE_PIN	AJ6 	        [get_ports 	{pcie_x16_txn[9]}	] ; 
set_property	PACKAGE_PIN	AG6 	        [get_ports 	{pcie_x16_txn[8]}	] ; 
set_property	PACKAGE_PIN	AM9 	        [get_ports 	{pcie_x16_txp[11]}	] ; 
set_property	PACKAGE_PIN	AL7	            [get_ports 	{pcie_x16_txp[10]}	] ; 
set_property	PACKAGE_PIN	AJ7 	        [get_ports 	{pcie_x16_txp[9]}	] ; 
set_property	PACKAGE_PIN	AG7 	        [get_ports 	{pcie_x16_txp[8]}	] ; 
set_property	PACKAGE_PIN	AU1 	        [get_ports 	{pcie_x16_rxn[7]}] ;  
set_property	PACKAGE_PIN	AT3 	        [get_ports 	{pcie_x16_rxn[6]}] ; 
set_property	PACKAGE_PIN	AR1 	        [get_ports 	{pcie_x16_rxn[5]}] ; 
set_property	PACKAGE_PIN	AP3 	        [get_ports 	{pcie_x16_rxn[4]}] ; 
set_property	PACKAGE_PIN	AU2 	        [get_ports 	{pcie_x16_rxp[7]}] ; 
set_property	PACKAGE_PIN	AT4 	        [get_ports 	{pcie_x16_rxp[6]}] ; 
set_property	PACKAGE_PIN	AR2 	        [get_ports 	{pcie_x16_rxp[5]}] ; 
set_property	PACKAGE_PIN	AP4 	        [get_ports 	{pcie_x16_rxp[4]}] ; 
set_property	PACKAGE_PIN	AH4	            [get_ports 	{pcie_x16_txn[7]}] ; 
set_property	PACKAGE_PIN	AE6 	        [get_ports 	{pcie_x16_txn[6]}] ; 
set_property	PACKAGE_PIN	AF4 	        [get_ports 	{pcie_x16_txn[5]}] ; 
set_property	PACKAGE_PIN	AD4	            [get_ports 	{pcie_x16_txn[4]}] ; 
set_property	PACKAGE_PIN	AH5	            [get_ports 	{pcie_x16_txp[7]}] ; 
set_property	PACKAGE_PIN	AE7 	        [get_ports 	{pcie_x16_txp[6]}] ; 
set_property	PACKAGE_PIN	AF5 	        [get_ports 	{pcie_x16_txp[5]}] ; 
set_property	PACKAGE_PIN	AD5	            [get_ports 	{pcie_x16_txp[4]}] ; 
set_property	PACKAGE_PIN	AN1 	        [get_ports 	{pcie_x16_rxn[3]}] ; 
set_property	PACKAGE_PIN	AK3 	        [get_ports 	{pcie_x16_rxn[2]}] ; 
set_property	PACKAGE_PIN	AM3 	        [get_ports 	{pcie_x16_rxn[1]}] ; 
set_property	PACKAGE_PIN	AL1 	        [get_ports 	{pcie_x16_rxn[0]}] ; 
set_property	PACKAGE_PIN	AN2 	        [get_ports 	{pcie_x16_rxp[3]}] ; 
set_property	PACKAGE_PIN	AK4 	        [get_ports 	{pcie_x16_rxp[2]}] ; 
set_property	PACKAGE_PIN	AM4 	        [get_ports 	{pcie_x16_rxp[1]}] ; 
set_property	PACKAGE_PIN	AL2 	        [get_ports 	{pcie_x16_rxp[0]}] ; 
set_property	PACKAGE_PIN	AC6 	        [get_ports 	{pcie_x16_txn[3]}] ; 
set_property	PACKAGE_PIN	AB4	            [get_ports 	{pcie_x16_txn[2]}] ; 
set_property	PACKAGE_PIN	AA6 	        [get_ports 	{pcie_x16_txn[1]}] ; 
set_property	PACKAGE_PIN	Y4	            [get_ports 	{pcie_x16_txn[0]}] ; 
set_property	PACKAGE_PIN	AC7 	        [get_ports 	{pcie_x16_txp[3]}] ; 
set_property	PACKAGE_PIN	AB5	            [get_ports 	{pcie_x16_txp[2]}] ; 
set_property	PACKAGE_PIN	AA7 	        [get_ports 	{pcie_x16_txp[1]}] ; 
set_property	PACKAGE_PIN	Y5	            [get_ports 	{pcie_x16_txp[0]}] ; 


