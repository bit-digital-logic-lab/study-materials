package ysyx

import chisel3._
import chisel3.util._

class Bcd7Seg extends Module {
  val io = IO(new Bundle {
    val num = Input(UInt(4.W))
    val out = Output(UInt(7.W))
  })

  io.out := 0.U
  switch(io.num) {
    is(0.U)  { io.out := "b0111111".U }
    is(1.U)  { io.out := "b0000110".U }
    is(2.U)  { io.out := "b1011011".U }
    is(3.U)  { io.out := "b1001111".U }
    is(4.U)  { io.out := "b1100110".U }
    is(5.U)  { io.out := "b1101101".U }
    is(6.U)  { io.out := "b1111101".U }
    is(7.U)  { io.out := "b0000111".U }
    is(8.U)  { io.out := "b1111111".U }
    is(9.U)  { io.out := "b1101111".U }
    is(10.U) { io.out := "b1110111".U }
    is(11.U) { io.out := "b1111100".U }
    is(12.U) { io.out := "b0111001".U }
    is(13.U) { io.out := "b1011110".U }
    is(14.U) { io.out := "b1111001".U }
    is(15.U) { io.out := "b1110001".U }
  }
}

class decode38 extends Module {
  val io = IO(new Bundle {
    val in = Input(Vec(8, UInt(1.W)))
    val out = Output(Vec(3, UInt(1.W)))
  })

  io.out(2) := 0.U
  io.out(1) := 0.U
  io.out(0) := 0.U

  // The first active input has priority.  The original input ordering is
  // kept: in(7) is the highest-priority input.
  when(io.in(7) === 1.U) {
    io.out(2) := 1.U
    io.out(1) := 1.U
    io.out(0) := 1.U
  }.elsewhen(io.in(6) === 1.U) {
    io.out(2) := 1.U
    io.out(1) := 1.U
  }.elsewhen(io.in(5) === 1.U) {
    io.out(2) := 1.U
    io.out(1) := 0.U
    io.out(0) := 1.U
  }.elsewhen(io.in(4) === 1.U) {
    io.out(2) := 1.U
  }.elsewhen(io.in(3) === 1.U) {
    io.out(1) := 1.U
    io.out(0) := 1.U
  }.elsewhen(io.in(2) === 1.U) {
    io.out(1) := 1.U
  }.elsewhen(io.in(1) === 1.U) {
    io.out(0) := 1.U
  }
}

class adder extends Module {
  val io = IO(new Bundle {
    val a = Input(SInt(8.W))
    val b = Input(SInt(8.W))
    val res = Output(SInt(9.W))
  })

  io.res := io.a +& io.b
}

class ALU extends Module {
  val io = IO(new Bundle {
    val op = Input(UInt(3.W))
    val a = Input(SInt(8.W))
    val b = Input(SInt(8.W))
    val res = Output(SInt(9.W))
  })

  io.res := 0.S
  switch(io.op) {
    is("b000".U) { io.res := io.a + io.b }
    is("b001".U) { io.res := io.a - io.b }
    is("b010".U) { io.res := ~io.a }
    is("b011".U) { io.res := io.a & io.b }
    is("b100".U) { io.res := io.a | io.b }
    is("b101".U) { io.res := io.a ^ io.b }
    is("b110".U) { io.res := Mux(io.a < io.b, 1.S, 0.S) }
    is("b111".U) { io.res := Mux(io.a === io.b, 1.S, 0.S) }
  }
}

class linear_feedbac_shift_reg extends Module {
  val io = IO(new Bundle {
    val out = Output(UInt(8.W))
  })

  val state = RegInit(1.U(8.W))
  val feedback = state(4) ^ state(3) ^ state(2) ^ state(0)

  state := Cat(feedback, state(7, 1))
  io.out := state
}

class shift extends Module {
  val io = IO(new Bundle {
    val op = Input(UInt(3.W))
    val in = Input(UInt(1.W))
    val out = Output(UInt(8.W))
  })

  val state = RegInit(0.U(8.W))
  state := state

  switch(io.op) {
    is("b000".U) { state := 0.U }
    is("b001".U) { state := "b11111111".U }
    is("b010".U) { state := Cat(0.U(1.W), state(7, 1)) }
    is("b011".U) { state := state << 1 }
    is("b100".U) { state := state >> 1 }
    is("b101".U) { state := Cat(io.in, state(7, 1)) }
    is("b110".U) { state := Cat(state(0), state(7, 1)) }
    is("b111".U) { state := Cat(state(6, 0), state(7)) }
  }

  io.out := state
}

class shift_plus extends Module {
  val io = IO(new Bundle {
    val num = Input(SInt(8.W))
    val op = Input(UInt(3.W))
    val left = Input(UInt(1.W))
    val logic = Input(UInt(1.W))
    val out = Output(SInt(8.W))
  })

  // Do the three possible shifts explicitly.  This is the same barrel
  // shifter as before, but avoids foldLeft and a Scala pattern match.
  val number = io.num.asUInt

  val left1 = Mux(io.op(0), (number << 1)(7, 0), number)
  val left2 = Mux(io.op(1), (left1 << 2)(7, 0), left1)
  val leftResult = Mux(io.op(2), (left2 << 4)(7, 0), left2)

  val logicalRight1 = Mux(io.op(0), number >> 1, number)
  val logicalRight2 = Mux(io.op(1), logicalRight1 >> 2, logicalRight1)
  val logicalRightResult = Mux(io.op(2), logicalRight2 >> 4, logicalRight2)

  val arithmeticRight1 = Mux(io.op(0), io.num >> 1, io.num)
  val arithmeticRight2 = Mux(io.op(1), arithmeticRight1 >> 2, arithmeticRight1)
  val arithmeticRightResult = Mux(io.op(2), arithmeticRight2 >> 4, arithmeticRight2)

  io.out := Mux(
    io.left.asBool,
    leftResult.asSInt,
    Mux(io.logic.asBool, logicalRightResult.asSInt, arithmeticRightResult)
  )
}

class simple_FSM extends Module {
  val io = IO(new Bundle {
    val SW0 = Input(Bool())
    val SW1 = Input(Bool())
    val KEY0 = Input(Bool())
    val LEDR0 = Output(Bool())
    val LEDR4 = Output(Bool())
    val LEDR5 = Output(Bool())
    val LEDR6 = Output(Bool())
    val LEDR7 = Output(Bool())
  })

  // State values A..I are 0..8, matching the old ChiselEnum encoding.
  val state = withClockAndReset((!io.KEY0).asClock, !io.SW0) {
    RegInit(0.U(4.W))
  }

  val nextState = Wire(UInt(4.W))
  nextState := 0.U

  switch(state) {
    is(0.U) { when(io.SW1) { nextState := 5.U }.otherwise { nextState := 1.U } }
    is(1.U) { when(io.SW1) { nextState := 5.U }.otherwise { nextState := 2.U } }
    is(2.U) { when(io.SW1) { nextState := 5.U }.otherwise { nextState := 3.U } }
    is(3.U) { when(io.SW1) { nextState := 5.U }.otherwise { nextState := 4.U } }
    is(4.U) { when(io.SW1) { nextState := 5.U }.otherwise { nextState := 4.U } }
    is(5.U) { when(io.SW1) { nextState := 6.U }.otherwise { nextState := 1.U } }
    is(6.U) { when(io.SW1) { nextState := 7.U }.otherwise { nextState := 1.U } }
    is(7.U) { when(io.SW1) { nextState := 8.U }.otherwise { nextState := 1.U } }
    is(8.U) { when(io.SW1) { nextState := 8.U }.otherwise { nextState := 1.U } }
  }

  state := nextState

  io.LEDR4 := state(3)
  io.LEDR5 := state(2)
  io.LEDR6 := state(1)
  io.LEDR7 := state(0)
  io.LEDR0 := state === 4.U || state === 8.U
}
