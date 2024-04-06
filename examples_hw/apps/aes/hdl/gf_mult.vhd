-------------------------------------------------------------------------
--  Copyright (C) 2018 Kaan Kara - Systems Group, ETH Zurich

--  This program is free software: you can redistribute it and/or modify
--  it under the terms of the GNU Affero General Public License as published
--  by the Free Software Foundation, either version 3 of the License, or
--  (at your option) any later version.

--  This program is distributed in the hope that it will be useful,
--  but WITHOUT ANY WARRANTY; without even the implied warranty of
--  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
--  GNU Affero General Public License for more details.

--  You should have received a copy of the GNU Affero General Public License
--  along with this program. If not, see <http://www.gnu.org/licenses/>.
----------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity gf_mult is
    generic (
        SELECTION : integer := 9
    );
    port (
        data_in  : in  std_logic_vector(7 downto 0);
        data_out : out std_logic_vector(7 downto 0)
    );
end entity gf_mult;

architecture behavioral of gf_mult is

signal x : integer range 0 to 15;
signal y : integer range 0 to 15;

type lookup_type is array(15 downto 0) of std_logic_vector(127 downto 0);
signal lookup : lookup_type;

begin

    SELECTION_9: if SELECTION = 9 generate
        lookup <= ( 
         0 => X"00_09_12_1b_24_2d_36_3f_48_41_5a_53_6c_65_7e_77",
         1 => X"90_99_82_8b_b4_bd_a6_af_d8_d1_ca_c3_fc_f5_ee_e7",
         2 => X"3b_32_29_20_1f_16_0d_04_73_7a_61_68_57_5e_45_4c",
         3 => X"ab_a2_b9_b0_8f_86_9d_94_e3_ea_f1_f8_c7_ce_d5_dc",
         4 => X"76_7f_64_6d_52_5b_40_49_3e_37_2c_25_1a_13_08_01",
         5 => X"e6_ef_f4_fd_c2_cb_d0_d9_ae_a7_bc_b5_8a_83_98_91",
         6 => X"4d_44_5f_56_69_60_7b_72_05_0c_17_1e_21_28_33_3a",
         7 => X"dd_d4_cf_c6_f9_f0_eb_e2_95_9c_87_8e_b1_b8_a3_aa",
         8 => X"ec_e5_fe_f7_c8_c1_da_d3_a4_ad_b6_bf_80_89_92_9b",
         9 => X"7c_75_6e_67_58_51_4a_43_34_3d_26_2f_10_19_02_0b",
        10 => X"d7_de_c5_cc_f3_fa_e1_e8_9f_96_8d_84_bb_b2_a9_a0",
        11 => X"47_4e_55_5c_63_6a_71_78_0f_06_1d_14_2b_22_39_30",
        12 => X"9a_93_88_81_be_b7_ac_a5_d2_db_c0_c9_f6_ff_e4_ed",
        13 => X"0a_03_18_11_2e_27_3c_35_42_4b_50_59_66_6f_74_7d",
        14 => X"a1_a8_b3_ba_85_8c_97_9e_e9_e0_fb_f2_cd_c4_df_d6",
        15 => X"31_38_23_2a_15_1c_07_0e_79_70_6b_62_5d_54_4f_46");
    end generate;

    SELECTION_11: if SELECTION = 11 generate
        lookup <= ( 
         0 => X"00_0b_16_1d_2c_27_3a_31_58_53_4e_45_74_7f_62_69",
         1 => X"b0_bb_a6_ad_9c_97_8a_81_e8_e3_fe_f5_c4_cf_d2_d9",
         2 => X"7b_70_6d_66_57_5c_41_4a_23_28_35_3e_0f_04_19_12",
         3 => X"cb_c0_dd_d6_e7_ec_f1_fa_93_98_85_8e_bf_b4_a9_a2",
         4 => X"f6_fd_e0_eb_da_d1_cc_c7_ae_a5_b8_b3_82_89_94_9f",
         5 => X"46_4d_50_5b_6a_61_7c_77_1e_15_08_03_32_39_24_2f",
         6 => X"8d_86_9b_90_a1_aa_b7_bc_d5_de_c3_c8_f9_f2_ef_e4",
         7 => X"3d_36_2b_20_11_1a_07_0c_65_6e_73_78_49_42_5f_54",
         8 => X"f7_fc_e1_ea_db_d0_cd_c6_af_a4_b9_b2_83_88_95_9e",
         9 => X"47_4c_51_5a_6b_60_7d_76_1f_14_09_02_33_38_25_2e",
        10 => X"8c_87_9a_91_a0_ab_b6_bd_d4_df_c2_c9_f8_f3_ee_e5",
        11 => X"3c_37_2a_21_10_1b_06_0d_64_6f_72_79_48_43_5e_55",
        12 => X"01_0a_17_1c_2d_26_3b_30_59_52_4f_44_75_7e_63_68",
        13 => X"b1_ba_a7_ac_9d_96_8b_80_e9_e2_ff_f4_c5_ce_d3_d8",
        14 => X"7a_71_6c_67_56_5d_40_4b_22_29_34_3f_0e_05_18_13",
        15 => X"ca_c1_dc_d7_e6_ed_f0_fb_92_99_84_8f_be_b5_a8_a3");
    end generate;
    
    SELECTION_13: if SELECTION = 13 generate
        lookup <= ( 
         0 => X"00_0d_1a_17_34_39_2e_23_68_65_72_7f_5c_51_46_4b",
         1 => X"d0_dd_ca_c7_e4_e9_fe_f3_b8_b5_a2_af_8c_81_96_9b",
         2 => X"bb_b6_a1_ac_8f_82_95_98_d3_de_c9_c4_e7_ea_fd_f0",
         3 => X"6b_66_71_7c_5f_52_45_48_03_0e_19_14_37_3a_2d_20",
         4 => X"6d_60_77_7a_59_54_43_4e_05_08_1f_12_31_3c_2b_26",
         5 => X"bd_b0_a7_aa_89_84_93_9e_d5_d8_cf_c2_e1_ec_fb_f6",
         6 => X"d6_db_cc_c1_e2_ef_f8_f5_be_b3_a4_a9_8a_87_90_9d",
         7 => X"06_0b_1c_11_32_3f_28_25_6e_63_74_79_5a_57_40_4d",
         8 => X"da_d7_c0_cd_ee_e3_f4_f9_b2_bf_a8_a5_86_8b_9c_91",
         9 => X"0a_07_10_1d_3e_33_24_29_62_6f_78_75_56_5b_4c_41",
        10 => X"61_6c_7b_76_55_58_4f_42_09_04_13_1e_3d_30_27_2a",
        11 => X"b1_bc_ab_a6_85_88_9f_92_d9_d4_c3_ce_ed_e0_f7_fa",
        12 => X"b7_ba_ad_a0_83_8e_99_94_df_d2_c5_c8_eb_e6_f1_fc",
        13 => X"67_6a_7d_70_53_5e_49_44_0f_02_15_18_3b_36_21_2c",
        14 => X"0c_01_16_1b_38_35_22_2f_64_69_7e_73_50_5d_4a_47",
        15 => X"dc_d1_c6_cb_e8_e5_f2_ff_b4_b9_ae_a3_80_8d_9a_97");
    end generate;

    SELECTION_14: if SELECTION = 14 generate
        lookup <= ( 
         0 => X"00_0e_1c_12_38_36_24_2a_70_7e_6c_62_48_46_54_5a",
         1 => X"e0_ee_fc_f2_d8_d6_c4_ca_90_9e_8c_82_a8_a6_b4_ba",
         2 => X"db_d5_c7_c9_e3_ed_ff_f1_ab_a5_b7_b9_93_9d_8f_81",
         3 => X"3b_35_27_29_03_0d_1f_11_4b_45_57_59_73_7d_6f_61",
         4 => X"ad_a3_b1_bf_95_9b_89_87_dd_d3_c1_cf_e5_eb_f9_f7",
         5 => X"4d_43_51_5f_75_7b_69_67_3d_33_21_2f_05_0b_19_17",
         6 => X"76_78_6a_64_4e_40_52_5c_06_08_1a_14_3e_30_22_2c",
         7 => X"96_98_8a_84_ae_a0_b2_bc_e6_e8_fa_f4_de_d0_c2_cc",
         8 => X"41_4f_5d_53_79_77_65_6b_31_3f_2d_23_09_07_15_1b",
         9 => X"a1_af_bd_b3_99_97_85_8b_d1_df_cd_c3_e9_e7_f5_fb",
        10 => X"9a_94_86_88_a2_ac_be_b0_ea_e4_f6_f8_d2_dc_ce_c0",
        11 => X"7a_74_66_68_42_4c_5e_50_0a_04_16_18_32_3c_2e_20",
        12 => X"ec_e2_f0_fe_d4_da_c8_c6_9c_92_80_8e_a4_aa_b8_b6",
        13 => X"0c_02_10_1e_34_3a_28_26_7c_72_60_6e_44_4a_58_56",
        14 => X"37_39_2b_25_0f_01_13_1d_47_49_5b_55_7f_71_63_6d",
        15 => X"d7_d9_cb_c5_ef_e1_f3_fd_a7_a9_bb_b5_9f_91_83_8d");
    end generate;

    x <= to_integer(unsigned(data_in(7 downto 4)));
    y <= 15 - to_integer(unsigned(data_in(3 downto 0)));

    data_out <= lookup(x)(y*8+7 downto y*8 ); 

end architecture;