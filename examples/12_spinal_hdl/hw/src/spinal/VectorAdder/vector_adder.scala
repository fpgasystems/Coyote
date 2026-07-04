/**
 * This file is part of Coyote <https://github.com/fpgasystems/Coyote>
 *
 * MIT Licence
 * Copyright (c) 2026, Systems Group, ETH Zurich
 * All rights reserved.
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files (the "Software"), to deal
 * in the Software without restriction, including without limitation the rights
 * to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 * copies of the Software, and to permit persons to whom the Software is
 * furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in all
 * copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 * OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
 * SOFTWARE.
 */

import spinal.core._
import spinal.lib._

case class AXIS() extends Bundle with IMasterSlave {
  val tdata  = Bits(512 bits)
  val tkeep  = Bits(64 bits)
  val tlast  = Bool()
  val tvalid = Bool()
  val tready = Bool()

  override def asMaster(): Unit = {
    out(tdata, tkeep, tlast, tvalid)
    in(tready)
  }
}

class VectorAdder extends Component {

  // Name of the generate verilog module
  setDefinitionName("vector_adder_spinal")

  // Clock, reset
  ClockDomain.current.clock.setName("aclk")
  ClockDomain.current.reset.setName("aresetn")

  // Define input and output streams
  val io = new Bundle {
    val s_axis_in1 = slave(AXIS())
    val s_axis_in2 = slave(AXIS())
    val m_axis_out = master(AXIS())
  }

  // Register inputs
  val in1_data  = Reg(Bits(512 bits)) init 0
  val in1_keep  = Reg(Bits(64 bits))  init 0
  val in1_last  = RegInit(False)
  val in1_valid = RegInit(False)

  val in2_data  = Reg(Bits(512 bits)) init 0
  val in2_keep  = Reg(Bits(64 bits))  init 0
  val in2_last  = RegInit(False)
  val in2_valid = RegInit(False)

  io.s_axis_in1.tready := !in1_valid
  io.s_axis_in2.tready := !in2_valid

  when(io.s_axis_in1.tvalid && io.s_axis_in1.tready) {
    in1_data  := io.s_axis_in1.tdata
    in1_keep  := io.s_axis_in1.tkeep
    in1_last  := io.s_axis_in1.tlast
    in1_valid := True
  }

  when(io.s_axis_in2.tvalid && io.s_axis_in2.tready) {
    in2_data  := io.s_axis_in2.tdata
    in2_keep  := io.s_axis_in2.tkeep
    in2_last  := io.s_axis_in2.tlast
    in2_valid := True
  }

  // Driver outputs
  val bothValid = in1_valid && in2_valid

  io.m_axis_out.tvalid := bothValid
  io.m_axis_out.tlast  := in1_last | in2_last
  io.m_axis_out.tkeep  := in1_keep & in2_keep
  for (i <- 0 until 16) {
    io.m_axis_out.tdata(i * 32, 32 bits) :=
      (in1_data(i * 32, 32 bits).asSInt + in2_data(i * 32, 32 bits).asSInt).asBits
  }

  // Clear buffers when output beat is consumed
  when(bothValid && io.m_axis_out.tready) {
    in1_valid := False
    in2_valid := False
  }
}

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