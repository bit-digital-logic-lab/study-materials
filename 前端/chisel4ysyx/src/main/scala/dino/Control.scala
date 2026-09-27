package dinocpu.components

import chisel3._
import chisel3.util._

object CtrlBits {
  val BRANCH       = 0
  val PCFROMALU    = 1
  val JUMP         = 2
  val MEMREAD      = 3
  val MEMWRITE     = 4
  val REGWRITE     = 5
  val TOREG        = 6

  val RESULTSEL_L  = 7
  val RESULTSEL_H  = 8

  val ALUSRC       = 9
  val PCADD        = 10
  val ITYPE        = 11

  val ALUOP_L      = 12
  val ALUOP_H      = 13

  val VALIDINST    = 14
}

object CtrlWord {
  val INVALID = "b0_00_0_0_0_00_0_0_0_0_0_0_0".U(15.W)

  // valid aluop itype pcadd alusrc result toreg regwrite memwrite memread jump pcfromalu branch
  val R       = "b1_10_0_0_0_00_0_1_0_0_0_0_0".U(15.W)

  // 以后继续加
  // val I     = ...
  // val LW    = ...
  // val SW    = ...
  // val BR    = ...
}

class Control extends Module {

  val io = IO(new Bundle {
    val opcode = Input(UInt(7.W))

    val branch       = Output(Bool())
    val pcfromalu    = Output(Bool())
    val jump         = Output(Bool())
    val memread      = Output(Bool())
    val memwrite     = Output(Bool())
    val regwrite     = Output(Bool())
    val toreg        = Output(UInt(1.W))
    val resultselect = Output(UInt(2.W))
    val alusrc       = Output(Bool())
    val pcadd        = Output(Bool())
    val itype        = Output(Bool())
    val aluop        = Output(UInt(2.W))
    val validinst    = Output(Bool())
  })

  //--------------------------------------------------
  // Control ROM
  //--------------------------------------------------

val ctrl = MuxLookup(io.opcode, CtrlWord.INVALID)(
  Seq(
    "b0110011".U(7.W) -> CtrlWord.R
  )
)

  //--------------------------------------------------
  // Decode Control Word
  //--------------------------------------------------

  val bits = ctrl.asBools

  io.branch       := bits(CtrlBits.BRANCH)
  io.pcfromalu    := bits(CtrlBits.PCFROMALU)
  io.jump         := bits(CtrlBits.JUMP)

  io.memread      := bits(CtrlBits.MEMREAD)
  io.memwrite     := bits(CtrlBits.MEMWRITE)

  io.regwrite     := bits(CtrlBits.REGWRITE)

  io.toreg        := ctrl(CtrlBits.TOREG).asUInt

  io.resultselect := ctrl(
    CtrlBits.RESULTSEL_H,
    CtrlBits.RESULTSEL_L
  )

  io.alusrc       := bits(CtrlBits.ALUSRC)
  io.pcadd        := bits(CtrlBits.PCADD)
  io.itype        := bits(CtrlBits.ITYPE)

  io.aluop := ctrl(
    CtrlBits.ALUOP_H,
    CtrlBits.ALUOP_L
  )

  io.validinst    := bits(CtrlBits.VALIDINST)
}
