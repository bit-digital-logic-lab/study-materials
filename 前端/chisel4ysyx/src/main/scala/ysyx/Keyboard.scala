package ysyx

import chisel3._ 
import chisel3.util._


class KeyboardLUT extends Module
{
  val io = IO(new Bundle {
    val input = Input(UInt(8.W))
    val output = Output(UInt(8.W))
  })
val normalScanToAscii = Seq(
  "h0e".U -> "h60".U, // `
  "h16".U -> "h31".U, // 1
  "h1e".U -> "h32".U, // 2
  "h26".U -> "h33".U, // 3
  "h25".U -> "h34".U, // 4
  "h2e".U -> "h35".U, // 5
  "h36".U -> "h36".U, // 6
  "h3d".U -> "h37".U, // 7
  "h3e".U -> "h38".U, // 8
  "h46".U -> "h39".U, // 9
  "h45".U -> "h30".U, // 0
  "h4e".U -> "h2d".U, // -
  "h55".U -> "h3d".U, // =

  "h15".U -> "h71".U, // q
  "h1d".U -> "h77".U, // w
  "h24".U -> "h65".U, // e
  "h2d".U -> "h72".U, // r
  "h2c".U -> "h74".U, // t
  "h35".U -> "h79".U, // y
  "h3c".U -> "h75".U, // u
  "h43".U -> "h69".U, // i
  "h44".U -> "h6f".U, // o
  "h4d".U -> "h70".U, // p
  "h54".U -> "h5b".U, // [
  "h5b".U -> "h5d".U, // ]
  "h5d".U -> "h5c".U, // \

  "h1c".U -> "h61".U, // a
  "h1b".U -> "h73".U, // s
  "h23".U -> "h64".U, // d
  "h2b".U -> "h66".U, // f
  "h34".U -> "h67".U, // g
  "h33".U -> "h68".U, // h
  "h3b".U -> "h6a".U, // j
  "h42".U -> "h6b".U, // k
  "h4b".U -> "h6c".U, // l
  "h4c".U -> "h3b".U, // ;
  "h52".U -> "h27".U, // '

  "h1a".U -> "h7a".U, // z
  "h22".U -> "h78".U, // x
  "h21".U -> "h63".U, // c
  "h2a".U -> "h76".U, // v
  "h32".U -> "h62".U, // b
  "h31".U -> "h6e".U, // n
  "h3a".U -> "h6d".U, // m
  "h41".U -> "h2c".U, // ,
  "h49".U -> "h2e".U, // .
  "h4a".U -> "h2f".U, // /

  "h29".U -> "h20".U, // Space
  "h0d".U -> "h09".U, // Tab
  "h5a".U -> "h0d".U, // Enter / CR
  "h66".U -> "h08".U, // Backspace
  "h76".U -> "h1b".U  // Escape
)


io.output := MuxLookup(io.input,0.U)(normalScanToAscii)
}

class HexToSevenSeg extends Module {
  val io = IO(new Bundle {
    val hex = Input(UInt(4.W))
    val en  = Input(Bool())
    val seg = Output(UInt(7.W))
  })

  // 低电平点亮，位序为 gfedcba
  val decoded = MuxLookup(io.hex, "b1111111".U(7.W))(Seq(
    "h0".U -> "b1000000".U,
    "h1".U -> "b1111001".U,
    "h2".U -> "b0100100".U,
    "h3".U -> "b0110000".U,
    "h4".U -> "b0011001".U,
    "h5".U -> "b0010010".U,
    "h6".U -> "b0000010".U,
    "h7".U -> "b1111000".U,
    "h8".U -> "b0000000".U,
    "h9".U -> "b0010000".U,
    "hA".U -> "b0001000".U,
    "hB".U -> "b0000011".U,
    "hC".U -> "b1000110".U,
    "hD".U -> "b0100001".U,
    "hE".U -> "b0000110".U,
    "hF".U -> "b0001110".U
  ))

  io.seg := Mux(io.en, decoded, "b1111111".U(7.W))
}


class receiver extends Module{
  val io = IO(new Bundle {
    val dataReady = Input(Bool())
    val data = Input(UInt(8.W))


    val nextdata_n = Output(Bool())
    
    val light1 = Output(UInt(7.W))
    val light2 = Output(UInt(7.W))
    val light3 = Output(UInt(7.W))
    val light4 = Output(UInt(7.W))
    val light5 = Output(UInt(7.W))
    val light6 = Output(UInt(7.W))

  })
  io.nextdata_n := !io.dataReady       
  val scanCode  = RegInit(0.U(8.W))
  val cnt    = RegInit(0.U(8.W))
  val flag_0 = RegInit(false.B)
  val flag_1 = RegInit(true.B)

  when(io.data === "hF0".U){
    flag_0 := 1.B
    flag_1 := 0.B
  }.elsewhen(flag_0 === 1.B && io.dataReady === 1.B){
    flag_1 := 1.B
    flag_0 := 0.B
  }.elsewhen(flag_1 === 1.U && io.dataReady === 1.B){
    cnt := cnt + 1.U
    flag_1 := 0.B
    flag_0 := 0.B
    scanCode := io.data
  }

  val en = !flag_0 && !flag_1
 

val lut = Module(new KeyboardLUT)
lut.io.input := scanCode

val ascii = lut.io.output

val seg1 = Module(new HexToSevenSeg)
val seg2 = Module(new HexToSevenSeg)
val seg3 = Module(new HexToSevenSeg)
val seg4 = Module(new HexToSevenSeg)
val seg5 = Module(new HexToSevenSeg)
val seg6 = Module(new HexToSevenSeg)

seg1.io.hex := cnt(7, 4)
seg1.io.en  := true.B

seg2.io.hex := cnt(3, 0)
seg2.io.en  := true.B

seg3.io.hex := ascii(7, 4)
seg3.io.en  := en

seg4.io.hex := ascii(3, 0)
seg4.io.en  := en

seg5.io.hex := scanCode(7, 4)
seg5.io.en  := en

seg6.io.hex := scanCode(3, 0)
seg6.io.en  := en

io.light1 := seg1.io.seg
io.light2 := seg2.io.seg
io.light3 := seg3.io.seg
io.light4 := seg4.io.seg
io.light5 := seg5.io.seg
io.light6 := seg6.io.seg

}
