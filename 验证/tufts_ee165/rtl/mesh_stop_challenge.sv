/* This is the mesh-stop code for the final debug challenge.
 */
module mesh_stop import mesh_defs::*; #(parameter MY_Y=0, MY_X=0)
	(input logic reset, clk, vert_link_dead,
	 input Ring_slot
		vert_ring_in,	// incoming vertical-ring data
		hori_ring_in,	// incoming horizontal-ring data
	 output Ring_slot
		vert_ring_out,	// drive vertical ring
		hori_ring_out,	// drive horizontal ring

	 output logic can_accept_data_from_env,	// data from the "rest of
	 input Ring_slot data_from_venv,	// the MS" to us

	 input logic venv_taking_data,	// Val env. is taking our data_to_venv
	 output Ring_slot data_to_venv,	// data from us to the "rest of the MS"
         output logic data_avail_for_venv);

  ////////////////////////////////////////////
  // Parameters for this mesh stop
  ////////////////////////////////////////////
  parameter N_FIFO_ADDR_BITS=2;	// So all FIFOs are 4 deep.

  ////////////////////////////////////////////
  // I/O signals for the three FIFOs.
  ////////////////////////////////////////////

  // FIFO buffering data_from_venv waiting to drive the mesh (Drv Fifo)
  Ring_slot DrvF_out;
  logic DrvF_rd_en, DrvF_wr_en, DrvF_empty, DrvF_full;

  // FIFO buffering incoming data from hori ring (HRx Fifo)
  Ring_slot HRxF_out;
  logic HRxF_rd_en, HRxF_wr_en, HRxF_empty, HRxF_full,
	HRxF_full_kill_wr_en, HRxF_pre_wr_en;
 
  // FIFO buffering incoming data from vert ring (VRx Fifo)
  Ring_slot VRxF_out;
  logic VRxF_rd_en, VRxF_wr_en, VRxF_empty, VRxF_full,
	VRxF_full_kill_wr_en, VRxF_pre_wr_en;

  ////////////////////////////////////////////
  // Where do the various FIFO outputs want to drive to?
  ////////////////////////////////////////////
  logic DrvF_wants_HRing, DrvF_wants_VRing,
	VRxF_wants_to_me, VRxF_wants_to_turn,
	HRxF_wants_to_me, HRxF_wants_to_turn;

  ////////////////////////////////////////////
  // I/O signals for the mux selects and outputs
  ////////////////////////////////////////////

  Ring_slot vert_mux_out, hori_mux_out;
  logic vert_sel_pass, vert_sel_me, vert_sel_turn;	//NEW vert_sel_turn
  logic hori_sel_pass, hori_sel_me, hori_sel_turn;
  logic dtvenv_sel_HRx_FIFO, dtvenv_sel_VRx_FIFO;
  logic HRingIn_wants_to_turn;				//NEW HRingIn_wants_to_turn

  ////////////////////////////////////////////
  // Datapath instantiation
  ////////////////////////////////////////////

   always_comb begin
    // Mux driving the vertical ring.
    unique if (vert_sel_pass)	vert_mux_out = vert_ring_in;
      else if (vert_sel_turn)	vert_mux_out = HRxF_out;	//NEW
      else if (vert_sel_me)	vert_mux_out = DrvF_out;
      else 			vert_mux_out = EMPTY_RING_SLOT;

    // Mux driving the horizontal ring.
    unique if (hori_sel_pass)	hori_mux_out = hori_ring_in;
      else if (hori_sel_turn)	hori_mux_out = VRxF_out;
      else if (hori_sel_me)	hori_mux_out = DrvF_out;
      else			hori_mux_out = EMPTY_RING_SLOT;

    // Mux driving this mesh stop's output to the verification environment
    // from the incoming vertical or horiz rings.
    unique if (dtvenv_sel_VRx_FIFO)	data_to_venv = VRxF_out;
      else if (dtvenv_sel_HRx_FIFO)	data_to_venv = HRxF_out;
      else 				data_to_venv = EMPTY_RING_SLOT;
  end	// always_comb

  // Flop the ring-driver-mux outputs
  always_ff @(posedge clk) begin
    if (reset) begin
	vert_ring_out <= EMPTY_RING_SLOT;
	hori_ring_out <= EMPTY_RING_SLOT;
    end else begin
	vert_ring_out <= vert_mux_out;
	hori_ring_out <= hori_mux_out;
    end
  end	// always_ff

  // Instantiate VRx Fifo
  fifo #(.DATA_TYPE(Ring_slot), .N_ADDR_BITS(N_FIFO_ADDR_BITS))
    VRxF(.reset(reset), .clk(clk),
	.wr_en(VRxF_wr_en), .rd_en(VRxF_rd_en),
	.wr_data(vert_ring_in), .rd_data(VRxF_out),
	.empty(VRxF_empty), .full(VRxF_full));

  // Instantiate HRx Fifo
  fifo #(.DATA_TYPE(Ring_slot), .N_ADDR_BITS(N_FIFO_ADDR_BITS))
    HRxF(.reset(reset), .clk(clk),
	.wr_en(HRxF_wr_en), .rd_en(HRxF_rd_en),
	.wr_data(hori_ring_in), .rd_data(HRxF_out),
	.empty(HRxF_empty), .full(HRxF_full));

  // Instantiate Drv Fifo
  fifo #(.DATA_TYPE(Ring_slot), .N_ADDR_BITS(N_FIFO_ADDR_BITS))
    DRV(.reset(reset), .clk(clk),
	.wr_en(DrvF_wr_en), .rd_en(DrvF_rd_en),
	.wr_data(data_from_venv), .rd_data(DrvF_out),
	.empty(DrvF_empty), .full(DrvF_full));

  ////////////////////////////////////////////
  // Control logic
  ////////////////////////////////////////////

  always_comb begin
    ////////////////////////////////////////////
    // Mux selects
    ////////////////////////////////////////////

    // Where does the DrvF output want to go (if anywhere)?
    DrvF_wants_HRing = !DrvF_empty && ((DrvF_out.dst_y==MY_Y)||vert_link_dead);
    DrvF_wants_VRing = !DrvF_empty && (DrvF_out.dst_y != MY_Y)
		     && !vert_link_dead;

    // Where does the VRxF output want to go (if anywhere)?
    // Note the VRx FIFO might be driving a ring turn onto a hori ring, in which
    // case we don't want to drive it to the verification env.
    VRxF_wants_to_turn = !VRxF_empty
		       && ((VRxF_out.dst_x!=MY_X) || (VRxF_out.dst_y!=MY_Y));
    VRxF_wants_to_me = !VRxF_empty
		     && (VRxF_out.dst_x == MY_X) && (VRxF_out.dst_y == MY_Y);

    // Where does the HRxF output want to go (if anywhere)?
    HRxF_wants_to_me = !HRxF_empty
		     && (HRxF_out.dst_x==MY_X) && (HRxF_out.dst_y==MY_Y);
    HRxF_wants_to_turn = !HRxF_empty && (HRxF_out.dst_y != MY_Y);

    // Vertical-ring-driver mux selects.
    // Sel_pass: an incoming vert packet that doesn't go into the VRxF had
    // better get passed along (or else it will be dropped).
    // And the link-broken case where we would have done a ring turn to the
    // hori ring, but it's broken.
    vert_sel_pass = vert_ring_in.valid && !vert_link_dead && !VRxF_wr_en;

    // Vert_sel_turn is for a packet that's doing an HRing-to-VRing turn, which
    // only happens if the packet is on the wrong row due to a dead VRing link.
    // We don't have to check vert_link_dead, since if it were dead then
    // HRingIn_wants_to_turn would not have asserted, and the packet would not
    // have entered the HRxF.
    vert_sel_turn = !vert_sel_pass && HRxF_wants_to_turn;

    // Sel_me: (Drv FIFO has a packet for the vert ring) & (a spot is open).
    // Note that !vert_sel_pass && !vert_sel_turn implements "a slot is open"
    // (or, alternately seen, ensures that the mux selects are prioritized).
    // The ring-turn case (vert_sel_turn) has priority over sel_me, since it's
    // often been waiting longer.
    vert_sel_me   = !vert_sel_pass && !vert_sel_turn && DrvF_wants_VRing;

    // Horizontal-ring-driver mux selects.
    // Sel_pass: same argument as above: any incoming hori packet that doesn't
    // go into the HRxF had better get passed along or else it will be dropped.
    hori_sel_pass = hori_ring_in.valid && !HRxF_wr_en;

    // Sel_turn: ring turn case has priority over sel_me, since arguably it's
    // been waiting longer. !Hori_sel_pass ensures mux-select prioritization;
    // i.e., ensures there's a ring slot open.
    hori_sel_turn = !hori_sel_pass && VRxF_wants_to_turn;

    // Sel_me: we're sending out a packet that doesn't need vertical routing and
    //	   a spot is still open after the two cases above.
    hori_sel_me   = !hori_sel_pass && !hori_sel_turn && DrvF_wants_HRing;

    // Data-to-mesh-stop mux. Yet again, the mux creates prioritization.
    dtvenv_sel_VRx_FIFO = VRxF_wants_to_me;
    dtvenv_sel_HRx_FIFO = !dtvenv_sel_VRx_FIFO && HRxF_wants_to_me;

    data_avail_for_venv = dtvenv_sel_VRx_FIFO || dtvenv_sel_HRx_FIFO;

    ////////////////////////////////////////////
    // Fifo rd/wr enables
    ////////////////////////////////////////////

    // Horizontal-ring-receiver FIFO read and write enables.
    // RdEn: The VRx Fifo has data that's being taken by one of its two readers.
    // The "vert_sel_turn" is new for broken links.
    HRxF_rd_en = (dtvenv_sel_HRx_FIFO && venv_taking_data) || vert_sel_turn;

    // There's an incoming hori packet that gets off at this column.
    HRingIn_wants_to_turn = hori_ring_in.valid && (hori_ring_in.dst_y!=MY_Y)
			      && (hori_ring_in.dst_x==MY_X) && !vert_link_dead;
    HRxF_pre_wr_en = (hori_ring_in.valid && (hori_ring_in.dst_x==MY_X))
		   || HRingIn_wants_to_turn;
    HRxF_full_kill_wr_en = HRxF_full && !HRxF_rd_en;	// So we will bounce
    HRxF_wr_en = HRxF_pre_wr_en && !HRxF_full_kill_wr_en;

    // Vertical-ring receiver FIFO read and write enables.
    // RdEn: the VRx Fifo has data that's being taken by one of its two readers.
    VRxF_rd_en = (dtvenv_sel_VRx_FIFO && venv_taking_data) || hori_sel_turn;

    // There's an incoming vertical packet that gets off at this row.
    // Or a vert-ring passthrough driving a broken link and forced to me.
    // Note the extra term for case 2.
    VRxF_pre_wr_en = vert_ring_in.valid
		   && ((vert_ring_in.dst_y==MY_Y) || vert_link_dead);
    VRxF_full_kill_wr_en = VRxF_full && !VRxF_rd_en;	// So we will bounce.
    VRxF_wr_en = VRxF_pre_wr_en && !VRxF_full_kill_wr_en;

    // Driver FIFO read and write enables.
    // RdEn: when either ring driver (vertical or horizontal) takes our data.
    DrvF_rd_en = hori_sel_me || vert_sel_me;
    // WrEn: whenever data comes into from our verification environment.
    DrvF_wr_en = data_from_venv.valid;
    // And tell the environment when we *cannot* take data
    can_accept_data_from_env = !DrvF_full || DrvF_rd_en;
  end	// always_comb
endmodule
