#### -- Set variables / configuration
global argv
global physOpt

source [lindex $argv 0]/scripts/settings.tcl

# Configure vivado for 8 threaded operation (8 threads maximum)
set_param general.maxThreads 8

set stage1Name "mcapshell"
set stage2Name "simpleshell"

set resourceDir "${baseDir}/resources"
set designDir "${baseDir}/designs/${designName}"
set buildDir "${designDir}/builds/${buildId}"

source $resourceDir/board-${boardName}/scripts/variables.tcl
source $resourceDir/scripts/functions.tcl

# Misc Configuration
set numMiners 1
set numClocks 1
set bitstreamNamespace 74657374
set bitstreamId 00000000

# Sec module path
set shell "simpleshell_${secImpl}_${numMiners}miners_${numClocks}clocks"
set secDir "${resourceDir}/board-${boardName}/components/${shell}"

# Source Paths
set shellTypesDir "${resourceDir}/stage2-miningshell/components/types/"
set shellTypeDir "${resourceDir}/stage2-miningshell/${stage2Name}/components/type-simple/"

# Mining Core Path
set miningCoreModule "$buildDir/${designName}_core_syn"

# Mining core cell path
set miningCoreCellPath "top_i/stage2_wrapper_i/stage2_i/hub_0/inst/mininglogic_i"

# Copy source code to build directory
file mkdir $buildDir/include
file copy -force $shellTypesDir $buildDir/include/shelltypes
file copy -force $shellTypeDir $buildDir/include/shelltype

#### -- Init project
# Starting to build project from here below
initProject

#### -- Synth Core
# Read shell types code
read_vhdl -vhdl2008 [glob "$buildDir/include/shelltypes/*.vhd"]
read_vhdl -vhdl2008 [glob "$buildDir/include/shelltype/*.vhd"]
# Read core design code
read_vhdl -vhdl2008 [glob "$buildDir/src/*.vhd"]
read_verilog [glob "$buildDir/src/core/*.v"]

# Update Compile Order
update_compile_order

## Synth core / design
# You may want to add a directive here
synth_design -mode out_of_context -flatten_hierarchy rebuilt -top mininglogic -part ${part} {*}$synthStrat

#set_max_delay 2.75 -to [get_pins -of [get_cells -hierarchical -filter {PRIMITIVE_SUBGROUP==BRAM}] -filter {BUS_NAME=~ADDR*}]

## Opt design
# Run opt_design here for un-integrated optimization
# opt_design -directive Default

# Save synth'd design
saveState ${miningCoreModule} -incremental_synth

## Integrate core
# Write meta info file
set metaInfoFile [open "${buildDir}/${designName}_core_meta.tcl" w]
puts $metaInfoFile "set numMiners $numMiners"
puts $metaInfoFile "set numClocks $numClocks"
close $metaInfoFile

# Read checkpoints
ensureBuilt "${resourceDir}/board-${boardName}/stage1-${stage1Name}/dcp/${stage1Name}_stage1_routed" "${resourceDir}/board-${boardName}/stage1-${stage1Name}" "syn"
openState "${resourceDir}/board-${boardName}/stage1-${stage1Name}/dcp/${stage1Name}_stage1_routed" "${resourceDir}/board-${boardName}/stage1-${stage1Name}" "strip"
read_checkpoint -cell top_i/stage2_wrapper_i "${secDir}/${stage2Name}_syn.dcp" -strict
read_checkpoint -cell $miningCoreCellPath "$miningCoreModule.dcp" -strict

set minerMgrs "top_i/stage2_wrapper_i/stage2_i/hub_0/inst/minermgrs\[*\].minermgr_i"

set_false_path -from [get_pins $minerMgrs/performed_hashes_reg\[*\]/C] -to [get_pins $minerMgrs/result_shellmsg_data_reg\[*\]/D]
set_false_path -from [get_pins $minerMgrs/cur_job_id_reg\[*\]/C] -to [get_pins $minerMgrs/result_shellmsg_data_reg\[*\]/D]
set_false_path -from [get_pins $minerMgrs/valid_reg/C] -to [get_pins $minerMgrs/valid_hist_reg*/D]
set_false_path -from [get_pins $minerMgrs/is_unlocked_reg/C] -to [get_pins $minerMgrs/result_accept_reg/D] -quiet
set_false_path -to [get_pins $minerMgrs/job_done_hist_reg\[0\]/D]
set_false_path -to [get_pins $minerMgrs/nonces_processed_clk_hist_reg\[0\]/D]

## Pre Implementation
# Run pre implementation configuration / scripts here.
# Generate core clock
set coreClk [create_clock -period 2.25 -name clkgen0_out -waveform {0.000 1.000} [get_pins $miningCoreCellPath/clkgen0/mmcm_mux/O]]

set_property CLOCK_DEDICATED_ROUTE FALSE [get_nets $miningCoreCellPath/clkgen*/mmcm*_out*]
set_false_path -to [get_pins $miningCoreCellPath/clkgen*/mmcm_mux/CE*]
set_false_path -from [get_pins $miningCoreCellPath/core/input/job_data_reg\[*\]*/C] -to $coreClk
set_false_path -to [get_pins $miningCoreCellPath/core/input/valid_capture_reg\[*\]/D]

set pbCore_blake [create_pblock pbCore_blake]
set_property PARENT $stage2Pblock $pbCore_blake
add_cells_to_pblock $pbCore_blake [get_cells $miningCoreCellPath/core/hash/blake]
resize_pblock $pbCore_blake -add {CLOCKREGION_X0Y10:CLOCKREGION_X2Y11}
resize_pblock $pbCore_blake -remove $stage1Sites

set pbCore_bmw [create_pblock pbCore_bmw]
set_property PARENT $stage2Pblock $pbCore_bmw
add_cells_to_pblock $pbCore_bmw [get_cells $miningCoreCellPath/core/hash/bmw]
resize_pblock $pbCore_bmw -add {CLOCKREGION_X3Y10:CLOCKREGION_X5Y11}
resize_pblock $pbCore_bmw -remove $stage1Sites

set pbCore_cube [create_pblock pbCore_cube]
set_property PARENT $stage2Pblock $pbCore_cube
add_cells_to_pblock $pbCore_cube [get_cells $miningCoreCellPath/core/hash/cube]
resize_pblock $pbCore_cube -add {CLOCKREGION_X0Y12:CLOCKREGION_X5Y14}
resize_pblock $pbCore_cube -remove $stage1Sites

set pbCore_groestl [create_pblock pbCore_groestl]
set_property PARENT $stage2Pblock $pbCore_groestl
add_cells_to_pblock $pbCore_groestl [get_cells $miningCoreCellPath/core/hash/groestl]
resize_pblock $pbCore_groestl -add {CLOCKREGION_X0Y0:CLOCKREGION_X5Y2}
resize_pblock $pbCore_groestl -remove $stage1Sites

set pbCore_jh [create_pblock pbCore_jh]
set_property PARENT $stage2Pblock $pbCore_jh
add_cells_to_pblock $pbCore_jh [get_cells $miningCoreCellPath/core/hash/jh]
resize_pblock $pbCore_jh -add {CLOCKREGION_X0Y3:CLOCKREGION_X2Y4}
resize_pblock $pbCore_jh -remove $stage1Sites

set pbCore_keccak [create_pblock pbCore_keccak]
set_property PARENT $stage2Pblock $pbCore_keccak
add_cells_to_pblock $pbCore_keccak [get_cells $miningCoreCellPath/core/hash/keccak]
resize_pblock $pbCore_keccak -add {CLOCKREGION_X3Y3:CLOCKREGION_X5Y4}
resize_pblock $pbCore_keccak -remove $stage1Sites

set pbCore_luffa [create_pblock pbCore_luffa]
set_property PARENT $stage2Pblock $pbCore_luffa
add_cells_to_pblock $pbCore_luffa [get_cells $miningCoreCellPath/core/hash/luffa]
resize_pblock $pbCore_luffa -add {CLOCKREGION_X0Y5:CLOCKREGION_X2Y7}
resize_pblock $pbCore_luffa -remove $stage1Sites

set pbCore_shavite [create_pblock pbCore_shavite]
set_property PARENT $stage2Pblock $pbCore_shavite
add_cells_to_pblock $pbCore_shavite [get_cells $miningCoreCellPath/core/hash/shavite]
resize_pblock $pbCore_shavite -add {CLOCKREGION_X3Y5:CLOCKREGION_X5Y7}
resize_pblock $pbCore_shavite -remove $stage1Sites

set pbCore_simd [create_pblock pbCore_simd]
set_property PARENT $stage2Pblock $pbCore_simd
add_cells_to_pblock $pbCore_simd [get_cells $miningCoreCellPath/core/hash/simd]
resize_pblock $pbCore_simd -add {CLOCKREGION_X0Y7:CLOCKREGION_X2Y9}
resize_pblock $pbCore_simd -remove $stage1Sites

set pbCore_skein [create_pblock pbCore_skein]
set_property PARENT $stage2Pblock $pbCore_skein
add_cells_to_pblock $pbCore_skein [get_cells $miningCoreCellPath/core/hash/skein]
resize_pblock $pbCore_skein -add {CLOCKREGION_X3Y8:CLOCKREGION_X5Y9}
resize_pblock $pbCore_skein -remove $stage1Sites

## Opt design
# Run opt_design here for integrated design optimization with known clock sources
# opt_design -directive Default

## Inject Rom
set romCell [get_cells top_i/stage2_wrapper_i/stage2_i/hub_0/inst/rom_i/rom]
binary scan [binary format H8H8 $bitstreamNamespace $bitstreamId] h* hex
set_property INIT_00 0x[string reverse $hex]6d6c6c41${boardId}000000016c6c656853656e696d6c6c41 $romCell
set_property INIT_01 0x00000000000010000000000000000000000001014d47694d6d6c6c4100100001 $romCell
set_property INIT_02 0x0000000000001000000000000000000000000001414e4458ffffffff00180001 $romCell

global numSLRs
for {set i 0} {$i < $numSLRs} {incr i} {
    set arg [format %08x [expr $i]]
    set baseaddr [format %08x [expr 0x1000 + 0x8 * $i]]
    set next [format %04x [expr 0x20 + 0x8 * $i]]
    set_property INIT_[format %02x [expr 3 + $i]] 0x${arg}${baseaddr}0000000000000000000000014e4d5358ffffffff${next}0001 $romCell
}

for {set i 0} {$i < $numMiners} {incr i} {
    set arg [format %08x [expr $i]]
    set baseaddr [format %08x [expr 0x10000 + 0x1000 * $i]]
    set next [format %04x [expr 0x20 + 0x8 * ($numSLRs + $i)]]
    set_property INIT_[format %02x [expr 3 + ($numSLRs + $i)]] 0x${arg}${baseaddr}0000000000000000000001014d43694d6d6c6c41${next}0001 $romCell
}

set_property INIT_[format %02x [expr 3 + ($numSLRs + $numMiners)]] 0x000000000000107800000000000000000000000255434d42ffffffff00000001 $romCell

# Save integrated synth design
saveState "${buildDir}/${designName}_syn"

report_timing_summary -file "${buildDir}/${designName}_timing_summary.rpt"
report_utilization -file "${buildDir}/${designName}_utilization_summary.rpt"

opt_design -dsp_register_opt -shift_register_opt -bufg_opt -resynth_seq_area -aggressive_remap

saveState "${buildDir}/${designName}_syn_opt"   

report_timing_summary -file "${buildDir}/${designName}_timing_summary.rpt"
report_utilization -file "${buildDir}/${designName}_utilization_summary.rpt"
