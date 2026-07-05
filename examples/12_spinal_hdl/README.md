# Coyote Example 12: SpinalHDL Vector Addition

Welcome to the twelth Coyote example! This example is a quick guide on synthesising SpinalHDL modules in Coyote.

Unlike the other examples, this README doesn't cover any new Coyote concepts - all of the concepts relavant to this example
are explain in the README of Example 2 (HLS Vector Addition). In fact, this example is a reimplementation of Example 2,
but instead of using HLS, it is using SpinalHDL.

Like HLS, Coyote will automatically pick up and synthesise all SpinalHDL modules, as long as the following steps are followed:
1. The scala files should be stored in the vFPGA source directory, in the sub-directory `scala`
2. Each module should be stored in a sub-directory which matches the Verilog generator defined in the scala file, e.g.,
the code for this module is stored in `hw/src/spinal/VectorAdder` and the generator config looks like:
```
// IMPORTANT: object name (without "Verilog") must match the folder name
object VectorAdderVerilog extends App {
  SpinalConfig(
    targetDirectory              = "gen",
    defaultClockDomainFrequency  = FixedFrequency(250 MHz),
    defaultConfigForClockDomains = ClockDomainConfig(
      resetKind        = SYNC,
      resetActiveLevel = LOW
    ),
    mergeAsyncProcess            = true
  ).generateVerilog(new VectorAdder)
}
```
3. The Verilog module name can be set through:
```
setDefinitionName("vector_adder_spinal")
```
It can then be instantiated in any other Verilog/SystemVerilog/VHDL file, just like any other RTL module.