/* This is the testbench for the final debug challenge.
 */

parameter MAX_PACKETS_PER_CYCLE=10;
parameter MESH_SIZE=4;		// For a 4x4 mesh.
parameter N_PACKETS_TO_SEND=40;	// How long the test will be
parameter DEAD_LINK_FREQ=4;	// 0=>links never dead; 10=>"all" links dead

import mesh_defs::*;		// Some common functions & definitions

`include "interface.sv"

class AbstractPacket;
    // First, the stuff we need.
    int unsigned data;				// the actual data
    int unsigned src_y, src_x, dst_y, dst_x;	// source and dest mesh stops

    // Add some meta-data. For a packet we generate, it may be which initial
    // mesh stop to launch the packet from (and may be different from src_y,
    // src_x if we want to test error conditions). For a packet we receive, it
    // may tell us which mesh stop actually received the packet (and may be
    // different from dst_y,dst_x if the mesh delivered the packet to the wrong
    // destination).
    int unsigned meta_y, meta_x;
    bit valid;

  function new (input int unsigned sy=0, sx=0, dy=0, dx=0, dt=0, val=0);
    src_y=sy; src_x=sx; dst_y=dy; dst_x=dx;
    data = dt;
    meta_y=sy; meta_x=sx; valid=val;
  endfunction : new

  // Typically used for printing an abstract packet.
  // 'Print_meta' says to print the meta-data also.
  function string str(int print_meta=0);
    string s;
    s = $sformatf("Data=%0d, valid=%0d, from y,x=(%0d,%0d) -> (%0d,%0d)",
	      this.data,this.valid,this.src_y,this.src_x,this.dst_y,this.dst_x);
    if (print_meta)
	s = $sformatf ("%s, Meta_y=%0d, meta_x=%0d", s,this.meta_y,this.meta_x);
    return (s);
  endfunction : str

  // SV doesn't natively provide a comparison on two objects of a class (other
  // than comparing their handles). Note we don't compare the meta-data.
  function equal (input AbstractPacket other);
    return ((this.src_y==other.src_y) && (this.src_x==other.src_x)
		&& (this.dst_y==other.dst_y) && (this.dst_x==other.dst_x)
		&& (this.data==other.data) && (this.valid==other.valid));
  endfunction : equal
endclass : AbstractPacket

/* The Generator class contains all of the knobs that control our RCG. It has
 * various knobs to target (or not target) the destination of the packets. When
 * we are targeting (e.g.,) a particular row of the mesh, it remembers which
 * row we're targeting. When we instantiate a Sim_control, we give it all of
 * these knob values.
 * Generator is also our runtime random-packet generator. It has the smarts to
 * generate lots of packets, over and over, that fit the distribution that the
 * knobs tell it to.
 */
class Generator;
  // Modes:
  //	1. purely random with no targeting
  //	2. target a single row (and with lots of packets traveling along that
  //	   row, any MS trying to launch from that row will likely be starved).
  //	3. target a single MS (so that MS likely has to bounce incoming packets)
  typedef enum int { NO_TARGET=0, TARGET_ROW=1, TARGET_MS=2 } Main_mode;
  Main_mode mode;

  // When we target (e.g.,) a single MS, that doesn't mean *all* of the packets
  // aim for that MS. Some should still go elsewhere. This variable says how
  // often to target -- if, e.g., how_often_to_target=9 then 9/10 of packets
  // will be targeted and 1/10 will not be.
  int how_often_to_target;	// must be in [0,10]

  // How often to launch new packets. See n_packets_to_launch() for details.
  int launch_freq;		// must be in [0,10*MAX_PACKETS_PER_CYCLE]

  // Once the fabric has a result ready for us, (take_results_frac/10) is the
  // odds we take that result in any given cycle. So 10 -> take it immediately.
  int take_results_frac;	// must be in [0,10]

  // The actual targets for the modes TARGET_ROW and TARGET_MS.
  int tgt_y, tgt_x;		// must be in [0,MESH_SIZE)

  // Get set up (i.e., pick the main mode & the main parameters) for packets for
  // the remainder of the test. This function gets called once at the beginning
  // of the test.
  function new (Main_mode main_md, int how_oft, tak_res_f, launch_f);
    assert ((how_oft>=0) && (how_oft<=10));
    assert ((tak_res_f>=0) && (tak_res_f<=10));
    assert (launch_f>=0);
    mode = main_md;
    how_often_to_target = how_oft;
    take_results_frac = tak_res_f;
    launch_freq = launch_f;

    // Pick target row & column (though we may not use them).
    this.srandom(1);
    $display ("%x%x%x%x\n", $urandom(), $urandom(), $urandom(), $urandom());
    tgt_x = $urandom_range(MESH_SIZE-1);
    tgt_y = $urandom_range(MESH_SIZE-1);
    $display ("Targets are row=%0d, col=%0d", tgt_y, tgt_x);
  endfunction : new

  // Decide how many packets to launch this cycle, as per the knob launch_freq.
  // Some examples of how the knob works:
  //	launch_freq=20 -> launch 2 packets. And 30 -> 3 packets, 40 -> 4, etc.
  //	launch_freq=27 -> 70% odds for 3, 30% odds for 2.
  // So for LF in [20,30), odds of (LF-20)/10 for 3 and (1-that) for 2.
  // This function is called only by Generator.make_packets(), and is not used
  // externally.
  function int n_packets_to_launch();
    int launch_floor, remainder, do_higher, how_many;
    launch_floor = launch_freq/10;	// these are integers, so it's a floor.
    remainder = launch_freq - (launch_floor*10);
    do_higher = ($urandom_range(10) < remainder);
    how_many = launch_floor + do_higher;
    assert (how_many <= MAX_PACKETS_PER_CYCLE);
    return (how_many);
  endfunction : n_packets_to_launch

  // Build one random packet. Generator.make_packets() calls this repeatedly to
  // build an array of random packets.
  function AbstractPacket random_packet();
    AbstractPacket AP;

    // Pick the source and destination mesh stops (not worrying about targets)
    AP = new();
    AP.src_x = $urandom_range(MESH_SIZE-1);
    AP.src_y = $urandom_range(MESH_SIZE-1);
    AP.dst_x = $urandom_range(MESH_SIZE-1);
    AP.dst_y = $urandom_range(MESH_SIZE-1);
    AP.data  = $urandom_range((1<<RING_DATA_WIDTH)-1);
    AP.valid = 1'b1;

    // Now take targets into account.
    if ((mode != NO_TARGET) && ($urandom_range(9)<how_often_to_target))
	AP.dst_y = tgt_y;
    if ((mode == TARGET_MS) && ($urandom_range(9)<how_often_to_target))
	AP.dst_x = tgt_x;

    // Don't allow routing to yourself!
    if ((AP.src_x==AP.dst_x) && (AP.src_y==AP.dst_y))
	AP.dst_y = (AP.dst_y + 1) % MESH_SIZE;

    //$display ("T=%0t: made random packet %s", $time, AP.str());
    return (AP);
  endfunction : random_packet

  // This is the main external function of the Generator class.
  function int make_packets(ref AbstractPacket AP_array[MAX_PACKETS_PER_CYCLE]);
    int n_packets, i;
    bit dup;
    AbstractPacket AP;
    n_packets = n_packets_to_launch();
    for (i=0; i< n_packets; i=i+0) begin
	AP_array[i] = random_packet();

	// It's not possible to launch multiple packets from one MS in a cycle.
	dup=0;
	for (int f=0; (f<i) && !dup; ++f)
	    if ((AP_array[f].src_x==AP_array[i].src_x)
			&& (AP_array[f].src_y==AP_array[i].src_y))
		dup = 1;
	if (!dup) ++i;
    end
    return (n_packets);
  endfunction : make_packets

  // This is the other external function of Generator.
  // Once the fabric has a result ready for us, (take_results_frac/10) is the
  // odds we take that result in any given cycle.
  function bit take_results();
    return ($urandom_range(9) < take_results_frac);
  endfunction : take_results
endclass : Generator

// We typically instantiate one Driver object, which takes an abstract packet
// from the Generator and sends it into the actual physical DUT interface.
class Driver;
  virtual If_mesh.TEST vif_mesh;
  function new (virtual If_mesh.TEST vif_mesh);
    this.vif_mesh = vif_mesh;
  endfunction : new

  // Stop sending the packets we sent last cycle. The mesh keys off our packet
  // having .valid=1, so we must set .valid to 0. We actually clear the entire
  // packet for ease of later debug.
  function void clear_all_mesh_inputs();
    for (int y=0; y<MESH_SIZE; ++y)
	for (int x=0; x<MESH_SIZE; ++x)
	    vif_mesh.data_from_venv[y][x] = EMPTY_RING_SLOT;
  endfunction : clear_all_mesh_inputs

  // This naturally belongs to the Driver class; it is talking to the DUT
  // detailed physical wires.
  task reset_DUT ();
    // Clear out the signals that we drive into the mesh, to avoid Xes.
    clear_all_mesh_inputs ();

    // Start the sim by doing a reset.
    $display ("Starting reset at t=%0t", $time);
    vif_mesh.reset = 1'b1;
    repeat (8) @(negedge vif_mesh.clk);
    //#160;
    vif_mesh.reset = 1'b0;
    $display ("Out of reset at t=%0t", $time);
  endtask : reset_DUT

  // Drive the main clock and set up waveform dumping.
  task drive_clock ();
      $dumpfile("dump.vcd");
      $dumpvars();
      vif_mesh.clk = 0;
      forever begin	// eventually someone will call $stop to end the sim.
          #10;
          vif_mesh.clk = ~vif_mesh.clk;
      end
  endtask : drive_clock

  // Send one cycle's worth of packets to the DUT. Don't tick the clock.
  function void drive_packets
	(input AbstractPacket AP_this_cycle[MAX_PACKETS_PER_CYCLE],
	 input int n_pack_this_cycle,	// how many we're given
	 inout int n_pack_sent,		// total sent ever
	 inout AbstractPacket packet_history [N_PACKETS_TO_SEND]);

    Ring_slot RS;		// Detailed physical packet
    AbstractPacket AP;		// Abstract packet from Generator

    // Stop sending any packets we sent last cycle. The mesh keys off
    // our packet having .valid=1, so set .valid to 0.
    // If we knew which packets got driven last cycle, we could just clear
    // those -- but here we just clear all of them.
    clear_all_mesh_inputs ();

    // Send the new packets
    for (int i=0; i<n_pack_this_cycle; ++i) begin
	// Inject this packet.
	AP = AP_this_cycle[i];
	RS.src_x=AP.src_x; RS.src_y=AP.src_y;
	RS.dst_x=AP.dst_x; RS.dst_y=AP.dst_y;
	RS.data = AP.data; RS.valid=1;
	RS.reserved=0; RS.unused=0;

	// If the DUT cannot take any packet, then just throw that
	// packet away (some other packet will get sent eventually).
	if (vif_mesh.can_accept_data_from_env[RS.src_y][RS.src_x]) begin
	    $display ("T=%0t: launching packet #%0d, %s",
		    $time, n_pack_sent, print_RS(RS));
	    packet_history[n_pack_sent] = AP; // Save it for later checking.
	    vif_mesh.data_from_venv[RS.src_y][RS.src_x] = RS;
	    n_pack_sent++;
	end
    end
  endfunction : drive_packets
endclass : Driver

class Monitor;
  virtual If_mesh.TEST vif_mesh;
  function new (virtual If_mesh.TEST vif_mesh);
    this.vif_mesh = vif_mesh;
  endfunction : new

  function void monitor_packets_this_cycle
	(inout AbstractPacket abs_packets_this_cycle[MESH_SIZE*MESH_SIZE],
	 output int n_packets,	// How many we found this cycle.
	 ref Generator GG);	// to call GG.take_results().

	int y, x;			// To loop through all mesh stops.
	Ring_slot RS;			// What we take from a mesh stop.
	AbstractPacket abs_packet;	// Build this for each RS we find.
	n_packets = 0;			// Total we found this cycle.

	// Check every mesh stop to see if a new packet has arrived this cycle.
	for (y=0; y<MESH_SIZE; ++y) begin
	    for (x=0; x<MESH_SIZE; ++x) begin
		if (! (vif_mesh.data_avail_for_venv[y][x] && GG.take_results()))
		begin
		    // Turn off any handshakes from last cycle.
		    vif_mesh.venv_taking_data[y][x]=0;
		    continue;
		end

		// At this point, we know that data_avail_for_venv[y][x]=1.
		// Start handshake to take the packet.
		vif_mesh.venv_taking_data[y][x]=1;

		// Create an abstract mesh packet from the physical one.
		RS = vif_mesh.data_to_venv[y][x];
		abs_packet=new(RS.src_y, RS.src_x, RS.dst_y,RS.dst_x,RS.data,1);
		// Use the meta fields to note where we found the packet.
		abs_packet.meta_y=y; abs_packet.meta_x=x;

		// Print it just for sanity.
		$display ("Monitor found physical %s", print_RS (RS));

		// Stuff it into the return array.
		abs_packets_this_cycle[n_packets++] = abs_packet;
	    end // for x
	end // for y
    endfunction : monitor_packets_this_cycle
endclass : Monitor

// Take the abstract packets we found this cycle, and check each one. Was it
// ever sent? Was it delivered to the correct destination?
class Checker;
  function void check_packets_this_cycle
	(input AbstractPacket abs_packets_this_cycle[MESH_SIZE*MESH_SIZE],
	 input int n_packets,
	 inout AbstractPacket packet_history[N_PACKETS_TO_SEND]);

    int x, y; // to loop through each MS and look for outgoing packets
    automatic int n_pack_recvd=0; // Track how many packets we've received.
    int match;			  // Index in packet_history of received packet
    AbstractPacket AP;

    for (int i=0; i < n_packets; ++i) begin
	AP = abs_packets_this_cycle[i];
	$display("T=%0T: Checker has %s", $time, AP.str(1));
	if ((AP.meta_y!=AP.dst_y) || (AP.meta_x!=AP.dst_x)) begin
	    $display("Packet delivered to wrong address -- ending simulation");
	    $stop;
	end
	match=-1;
	for (int j=0; (j<N_PACKETS_TO_SEND)&& (match<0); ++j) begin
	    //$display ("Comparing against packet_history[%0d]", j);
	    //$display ("%s", packet_history[j].str(1));
	    if (packet_history[j].valid	&& packet_history[j].equal(AP)) begin
		packet_history[j].valid = 1'b0;	// Mark as found.
		match=j;
		$display ("\tMatched packet #%0d", match);
	    end
	end	// checking if found
	if (match<0) begin
	    $display("Packet received but not sent -- ending simulation");
	    $stop;
	end
    end
  endfunction : check_packets_this_cycle
endclass : Checker

class Testbench;
  Generator GG;
  Driver DD;
  Monitor MM;
  Checker CC;
  int n_packets_received;
  virtual If_mesh.TEST vif_mesh;

  // Build up the testbench.
  function void build (virtual If_mesh.TEST vif_mesh,
		       inout AbstractPacket packet_history[N_PACKETS_TO_SEND]);
    this.vif_mesh = vif_mesh;
    GG = new(.main_md(Generator::TARGET_MS), // type of targeting
		.how_oft(10),	// how often to target
		.tak_res_f(10),	// how often to take results
		.launch_f(20));	// how often to launch a new packet

    DD = new(vif_mesh);	// Driver
    MM = new(vif_mesh);	// Monitor
    CC = new();	// Checker

    // Clear the packet history before we start filling it.
    for (int i=0; i<N_PACKETS_TO_SEND; ++i)
	packet_history[i] = new();
    n_packets_received = 0;
  endfunction : build

  // The main loop for the generator and driver. The generator builds random
  // abstract packets; the driver sends them to the DUT's physical interface.
  task generator_driver_loop (
	 ref Generator GG, ref Driver DD,
	 ref AbstractPacket packet_history [N_PACKETS_TO_SEND]);
    automatic int
	n_packets_sent=0,	// total ever sent, to know when to stop sending
	n_packets_this_cycle=0;	// number to send in the current cycle
    AbstractPacket AP_this_cycle[MAX_PACKETS_PER_CYCLE];  // to send right now
    $display ("In Testbench.generator_driver_loop() at t=%0t", $time);

    // Main loop -- send the packets.
    forever begin	// Not an infinite loop; there's a 'break' inside.
	// Exit from the "forever" loop here (rather than at the top of the
	// loop) to ensure that the final packets we send do get their
	// data_from_venv.valid signals cleared.
	if (n_packets_sent>=N_PACKETS_TO_SEND) break;

	// Get new packets for this cycle, and ensure there's not too many.
	n_packets_this_cycle = GG.make_packets (AP_this_cycle);
	if (n_packets_sent+n_packets_this_cycle > N_PACKETS_TO_SEND)
	    n_packets_this_cycle = N_PACKETS_TO_SEND-n_packets_sent;

	DD.drive_packets
	  (AP_this_cycle, n_packets_this_cycle, n_packets_sent, packet_history);

	@(negedge vif_mesh.clk);
    end; // while not all packets sent

    $display ("Done launching packets at t=%0t", $time);

    // Stop sending the packets we sent last cycle. The mesh keys off
    // our packet having .valid=1, so set .valid to 0.
    for (int y=0; y<MESH_SIZE; ++y)
	for (int x=0; x<MESH_SIZE; ++x)
	    vif_mesh.data_from_venv[y][x].valid = 0;

    // Allow a few cycles for the sim to finish after we stop sending packets,
    // and then kill it. This ensures that we don't hang if the checker fails
    // to stop the sim (e.g., if we lose a packet).
    repeat (500) @(negedge vif_mesh.clk);
    // If the checker finds all packets, then it stops the sim before we reach
    // here.
    $display ("Unsuccessful sim: not all packets received. Ending sim at t=%0t: ", $time);
    $stop;
  endtask : generator_driver_loop

  // The main loop for monitor and checker.
  // The monitor receives packets from the mesh (which involves a handshake).
  // The checker then checks that the packets were sent correctly.
  task monitor_checker_loop
    (ref Generator GG,
     ref AbstractPacket packet_history [N_PACKETS_TO_SEND]);

    // Communication between the monitor and checker.
    AbstractPacket abs_packets_this_cycle[MESH_SIZE*MESH_SIZE];
    int n_packets;

    // Weird stuff can happen during reset, so don't start looking for packets
    // until that's done.
    while (vif_mesh.reset == 1'b1)
	@(negedge vif_mesh.clk);

    // The outer loop (i.e., the "forever" block) runs forever; it keeps
    // checking if new packets have arrived at any mesh stop, and if so checks
    // that the packet was previously sent. It stops when it successfully
    // receives all packets, or when generator_driver_loop() calls $stop.
    forever begin
	@(negedge vif_mesh.clk);
	MM.monitor_packets_this_cycle (abs_packets_this_cycle, n_packets, GG);
	CC.check_packets_this_cycle (abs_packets_this_cycle,n_packets,
				     packet_history);
	n_packets_received += n_packets;
	if (n_packets_received == N_PACKETS_TO_SEND) begin
	    $display("Received all %0d packets; successfully ending simulation",
		     N_PACKETS_TO_SEND);
	    return;
	end
    end // while all packets not received yet.
  endtask : monitor_checker_loop

  task run_sim (ref AbstractPacket packet_history [N_PACKETS_TO_SEND]);
    // With fork/join_any, the main thread pauses until the first of the three
    // forked children finishes. The first child is drive_clock(), which never
    // finishes. The second is reset_DUT() (which is fast), and
    // generator_driver_loop() (which sends all of the packets, waits a few
    // hundred cycles, and kills the sim). Our real preference is that
    // monitor_checker_loop() ends first upon successfully finding all packets.
    // In that case, the fork/join_any moves on, run_sim() returns, and our
    // caller then does any desired cleanup.
    fork
	DD.drive_clock ();
	begin
	  DD.reset_DUT ();
	  generator_driver_loop (GG, DD, packet_history);
	end

	monitor_checker_loop (GG, packet_history);
    join_any;
    $display ("Run_sim is returning.");
  endtask : run_sim

  function void cleanup();
    $display ("Simulation done; in testbench.cleanup()");
  endfunction : cleanup

endclass : Testbench

// Begin the top-level module for the testbench plus DUT.
module automatic top_level;

  // Declare the interface signals to the mesh.
  If_mesh if_mesh();

  // As we launch packets, we'll save them here so we can check them later.
  AbstractPacket packet_history [N_PACKETS_TO_SEND];

  // Instantiate the NxN mesh
  mesh_NxN #(.N(MESH_SIZE)) M_NxN (if_mesh.DUT);

  initial begin
      // Instantiate the testbench.
      automatic Testbench TB = new();

      TB.build(if_mesh.TEST, packet_history);
      TB.run_sim (packet_history);
      TB.cleanup();
      $stop;
  end

  // This module is to help you debug your mesh stop and/or RCG. It just dumps
  // out all valid packets on the vertical or horizontal rings every cycle.
  // Hopefully the code is fairly self-explanatory; feel free to modify it for
  // your use. You could change the printing format, add some "if" statements
  // to restrict what data gets printed, etc.
  // Note that all printing happens on the *falling* clock edge.
  initial begin : debugger
    Ring_slot RS;
    int y, x;

    // Weird stuff can happen during reset, so don't start looking for packets
    // until that's done.
    while (if_mesh.reset == 1'b1)
	@(negedge if_mesh.clk);

    forever begin
	@(negedge if_mesh.clk);
        for (y=0; y<MESH_SIZE; ++y) begin
	  for (x=0; x<MESH_SIZE; ++x) begin
	    RS = top_level.M_NxN.vert_ring[y][x];
	    if (RS.valid)
	      $display("\tdbg T=%0t: vert[%0d][%0d]=%s",$time,y,x,print_RS(RS));
	    RS = top_level.M_NxN.hori_ring[y][x];
	    if (RS.valid)
	      $display("\tdbg T=%0t: hori[%0d][%0d]=%s",$time,y,x,print_RS(RS));
	  end
	end
    end
  end : debugger

  // NEW CODE to manage dead links.
  initial begin : dead_links
    // Set up any broken links (i.e., set tb_mesh.M_NxN.vert_link_dead[]).
    // * Look at dead_link_freq to control how often we randomly kill a link.
    // * Never kill all the vertical links leaving any row (that would break the
    //   mesh)
    bit dead;
    int n_dead;
    for (int y=0; y<MESH_SIZE; ++y) begin
        n_dead = 0;
	for (int x=0; x<MESH_SIZE; ++x) begin
	    // dead_link_freq=0 => none dead. And 10 => all dead.
	    dead = ($urandom_range(9)<DEAD_LINK_FREQ) && (n_dead+1<MESH_SIZE);
	    top_level.M_NxN.vert_link_dead[y][x] = dead;
	    n_dead += dead;
	end
    end

    // Display what's dead, to help with debugging.
    for (int y=0; y<MESH_SIZE; ++y)
	for (int x=0; x<MESH_SIZE; ++x)
	    if (top_level.M_NxN.vert_link_dead[y][x] == 1)
		$display ("Set dead link %0d,%0d", y, x);

    // As usual, wait until reset is done.
    while (if_mesh.reset == 1'b1)
	@(negedge if_mesh.clk);

    // At every falling edge for the entire sim, ensure that the dead links are
    // being respected -- i.e., that the MSs aren't actually driving on them.
    forever begin
	@(negedge if_mesh.clk);
        for (int y=0; y<MESH_SIZE; ++y) begin
	    for (int x=0; x<MESH_SIZE; ++x) begin
		if (top_level.M_NxN.vert_link_dead[y][x])
		    assert (top_level.M_NxN.vert_ring[y][x].valid==0);
	    end
	end
    end
  end : dead_links
  // END OF NEW CODE to manage dead links.
endmodule : top_level
