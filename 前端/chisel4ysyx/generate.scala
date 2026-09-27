package ysyx

import circt.stage.ChiselStage

object GenAll extends App {
  ChiselStage.emitSystemVerilogFile(
    new Bcd7Seg,
    Array("--target-dir", "generated")
  )

  ChiselStage.emitSystemVerilogFile(
    new decode38,
    Array("--target-dir", "generated")
  )

  ChiselStage.emitSystemVerilogFile(
    new adder,
    Array("--target-dir", "generated")
  )

  ChiselStage.emitSystemVerilogFile(
    new ALU,
    Array("--target-dir", "generated")
  )

  ChiselStage.emitSystemVerilogFile(
    new linear_feedbac_shift_reg,
    Array("--target-dir", "generated")
  )

  ChiselStage.emitSystemVerilogFile(
    new shift,
    Array("--target-dir", "generated")
  )

  ChiselStage.emitSystemVerilogFile(
    new shift_plus,
    Array("--target-dir", "generated")
  )
}
