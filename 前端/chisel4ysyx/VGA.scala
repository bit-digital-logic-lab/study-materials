package ysyx

import chisel3._ 
import chisel3.util._




final case class SpriteConfig(
  width:  Int = 128,
  height: Int = 128,
  speedX: Int = 2,
  speedY: Int = 1)





class VGA(cfg: SpriteConfig = SpriteConfig()) extends Module{
  val io = IO(new Bundle {
    val pclk = Input(Clock())
    val reset = Input(Bool())


    val vga_data = Input(UInt(24.W))

    val h_addr = Output(UInt(10.W))
    val v_addr = Output(UInt(10.W))

    val hsync  = Output(Bool())
    val vsync  = Output(Bool())

    val valid  = Output(Bool())

    val vga_r  = Output(UInt(8.W))
    val vga_g  = Output(UInt(8.W))
    val vga_b  = Output(UInt(8.W))

  })


withClockAndReset(io.pclk, io.reset) {


  val maxx = 640 - cfg.width 
 val maxy = 480 - cfg.height 


  val baseX = RegInit(11.U(10.W))
  val baseY = RegInit(11.U(10.W))

  val flagX = RegInit(0.U(1.W))
  val flagY = RegInit(0.U(1.W))


val hCount = RegInit(0.U(10.W))
val vCount = RegInit(0.U(10.W))

val localX = hCount - baseX
val localY = vCount - baseY

  val nextscan = hCount === 799.U && vCount === 524.U



//counter


when(hCount =/= 799.U && vCount =/= 524.U){
  hCount := hCount +1.U


}.elsewhen(hCount === 799.U && vCount =/= 524.U){


  hCount :=0.U
  vCount := vCount + 1.U
}.elsewhen(hCount =/= 799.U && vCount === 524.U){
  hCount := hCount +1.U


  }.otherwise{
  hCount := 0.U
  vCount := 0.U

}

val buding = RegInit(false.B)

  //base and move

  when(nextscan){
    when(buding === 0.U &&( baseX < 10.U || baseX >maxx.U || baseY < 10.U || baseY >maxy.U))
    {
    when(baseX < 10.U || baseX >=maxx.U){
      flagX := ~flagX
      when(baseX <10.U){
      }
    }
    when(baseY < 10.U || baseY >=maxy.U){
      flagY := ~flagY
    }
    buding := 1.U
    }.otherwise{
      buding := 0.U

       when(baseX < maxx.U && flagX === 0.B || baseX < 10.U ){
      baseX := baseX + cfg.speedX.U
    }.otherwise{
      baseX := baseX - cfg.speedX.U
    }
    when(baseY < maxy.U && flagY === 0.B || baseY < 10.U ){
      baseY := baseY + cfg.speedY.U
    }.otherwise{
      baseY := baseY - cfg.speedY.U
    }


    }


  }



val active = hCount < 640.U && vCount < 480.U
io.valid := active
io.hsync := !(hCount >= 656.U && hCount < 752.U)
io.vsync := !(vCount >= 490.U && vCount < 492.U)

//picture
val inside =
  active &&
  hCount >= baseX &&
  hCount < baseX + cfg.width.U &&
  vCount >= baseY &&
  vCount < baseY + cfg.height.U



io.h_addr := Mux(inside, localX, 0.U)
io.v_addr := Mux(inside, localY, 0.U)


val pixelData = Mux(inside, io.vga_data, 0.U(24.W))

io.vga_r := pixelData(23, 16)
io.vga_g := pixelData(15, 8)
io.vga_b := pixelData(7, 0)



}
}
