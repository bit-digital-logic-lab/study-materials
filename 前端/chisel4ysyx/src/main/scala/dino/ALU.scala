package dinocpu.components
import chisel3._ 
import chisel3.util._


class ALUControl extends Module {
  val io = IO(new Bundle {
    val aluop       = Input(UInt(2.W))
    val arth_type   = Input(UInt(1.W))
    val int_length  = Input(UInt(1.W))
    val funct7      = Input(UInt(7.W))
    val funct3      = Input(UInt(3.W))

    val operation   = Output(UInt(5.W))
  })
  // 11100 未使用


  object op {
  val add = "b00000".U


  }

  val key = Cat (
      io.arth_type,
      io.int_length,
      io.funct7,
      io.funct3
    )


  val table = Seq(
    "?_?_???????_???".U -> "?????".U
    )


  io.operation  :=  MuxLookup(
    key,
    "11111".U)(
    table
    )
    

}
