`include "uvm_macros.svh"
import uvm_pkg::*;

//INTERFACE
interface axi4_if(input logic clk);
  logic rstn;

  logic [3:0]  aw_id;
  logic [31:0] aw_addr;
  logic [7:0]  aw_len;
  logic [2:0]  aw_size;
  logic [1:0]  aw_burst;
  logic        aw_valid;
  logic        aw_ready;

  logic [31:0] w_data;
  logic [3:0]  w_strb;
  logic        w_last;
  logic        w_valid;
  logic        w_ready;

  logic [3:0]  b_id;
  logic [1:0]  b_resp;
  logic        b_valid;
  logic        b_ready;

  logic [3:0]  ar_id;
  logic [31:0] ar_addr;
  logic [7:0]  ar_len;
  logic [2:0]  ar_size;
  logic [1:0]  ar_burst;
  logic        ar_valid;
  logic        ar_ready;

  logic [3:0]  r_id;
  logic [31:0] r_data;
  logic [1:0]  r_resp;
  logic        r_last;
  logic        r_valid;
  logic        r_ready;
endinterface


//SEQUENCE ITEM
typedef enum bit {WRITE, READ} trans_type_e;

class axi4_seq_item extends uvm_sequence_item;
  `uvm_object_utils(axi4_seq_item)

  function new(string name = "axi4_seq_item");
    super.new(name);
  endfunction

  rand trans_type_e trans_type;
  rand bit [31:0] addr;
  rand bit [7:0]  len;
  rand bit [3:0]  id;
  rand bit [1:0]  burst;
  rand bit [3:0]  strb;

  rand bit [31:0] data_q[$];
       bit [1:0]  resp;
endclass


//SEQUENCE
//WRITE
class axi4_write_sequence extends uvm_sequence #(axi4_seq_item);
  `uvm_object_utils(axi4_write_sequence)

  function new(string name = "axi4_write_sequence");
    super.new(name);
  endfunction

  task body();
    axi4_seq_item item;
    bit [31:0] beat_vals[4] = '{32'h11, 32'h22, 32'h33, 32'h44};
    item = axi4_seq_item::type_id::create("item");

    start_item(item);
    item.trans_type = WRITE;
    item.addr  = 32'h0000_0000;
    item.id    = 4'h1;
    item.len   = 3;
    item.burst = 2'b01;
    item.strb  = 4'hF;

    for (int i = 0; i <= item.len; i++) begin
      item.data_q.push_back(beat_vals[i]);
    end
    finish_item(item);
  endtask
endclass

//READ
class axi4_read_sequence extends uvm_sequence #(axi4_seq_item);
  `uvm_object_utils(axi4_read_sequence)

  function new(string name = "axi4_read_sequence");
    super.new(name);
  endfunction

  task body();
    axi4_seq_item item;
    item = axi4_seq_item::type_id::create("item");

    start_item(item);
    item.trans_type = READ;
    item.addr  = 32'h0000_0000;
    item.id    = 4'h1;
    item.len   = 3;
    item.burst = 2'b01;
    finish_item(item);
  endtask
endclass


//DRIVER
class axi4_driver extends uvm_driver #(axi4_seq_item);
  `uvm_component_utils(axi4_driver)

  virtual axi4_if vif;
  axi4_seq_item req;

  function new(string name = "axi4_driver", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db#(virtual axi4_if)::get(this, "", "vif", vif))
      `uvm_fatal("NOVIF", "vif not found for driver")
  endfunction

  task aw_handshake(axi4_seq_item item);
    vif.aw_addr  = item.addr;
    vif.aw_id    = item.id;
    vif.aw_len   = item.len;
    vif.aw_burst = item.burst;
    vif.aw_valid = 1;
    @(posedge vif.clk);
    while (!vif.aw_ready) @(posedge vif.clk);
    vif.aw_valid = 0;
  endtask

  task w_handshake(axi4_seq_item item);
    for (int i = 0; i <= item.len; i++) begin
      vif.w_data  = item.data_q[i];
      vif.w_strb  = item.strb;
      vif.w_last  = (i == item.len);
      vif.w_valid = 1;
      @(posedge vif.clk);
      while (!vif.w_ready) @(posedge vif.clk);
      vif.w_valid = 0;
    end
  endtask

  task b_handshake(axi4_seq_item item);
    vif.b_ready = 1;
    @(posedge vif.clk);
    while (!vif.b_valid) @(posedge vif.clk);
    item.resp   = vif.b_resp;
    vif.b_ready = 0;
  endtask

  task ar_handshake(axi4_seq_item item);
    vif.ar_addr  = item.addr;
    vif.ar_id    = item.id;
    vif.ar_len   = item.len;
    vif.ar_burst = item.burst;
    vif.ar_valid = 1;
    @(posedge vif.clk);
    while (!vif.ar_ready) @(posedge vif.clk);
    vif.ar_valid = 0;
  endtask

  task r_handshake(axi4_seq_item item);
  bit last;
  item.data_q.delete();
  last = 0;
  vif.r_ready = 1;
  while (!last) begin
    @(posedge vif.clk);
    if (vif.r_valid) begin
      item.data_q.push_back(vif.r_data);
      item.resp = vif.r_resp;
      last      = vif.r_last;
      $display("T=%0t: R beat captured, data=%0h, last=%0b", $time, vif.r_data, last);
    end
  end
  vif.r_ready = 0;
endtask

  task drive_write(axi4_seq_item item);
    aw_handshake(item);
    w_handshake(item);
    b_handshake(item);
  endtask

  task drive_read(axi4_seq_item item);
    ar_handshake(item);
    r_handshake(item);
  endtask

  task run_phase(uvm_phase phase);
  forever begin
    seq_item_port.get_next_item(req);
    $display("T=%0t: Driver got item, trans_type=%s", $time, req.trans_type.name());
    if (req.trans_type == WRITE)
      drive_write(req);
    else
      drive_read(req);
    $display("T=%0t: Driver finished item, calling item_done", $time);
    seq_item_port.item_done();
  end
  endtask
    endclass


//MONITOR
class axi4_monitor extends uvm_monitor;
  `uvm_component_utils(axi4_monitor)

  virtual axi4_if vif;
  uvm_analysis_port #(axi4_seq_item) ap;

  function new(string name = "axi4_monitor", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    ap = new("ap", this);
    if (!uvm_config_db#(virtual axi4_if)::get(this, "", "vif", vif))
      `uvm_fatal("NOVIF", "vif not found for monitor")
  endfunction

  task run_phase(uvm_phase phase);
    fork
      monitor_write();
      monitor_read();
    join_none
  endtask

  task monitor_write();
    forever begin
      axi4_seq_item item;
      item = axi4_seq_item::type_id::create("item");
      item.trans_type = WRITE;

      @(posedge vif.clk);
      while (!(vif.aw_valid && vif.aw_ready)) @(posedge vif.clk);
      item.addr  = vif.aw_addr;
      item.id    = vif.aw_id;
      item.len   = vif.aw_len;
      item.burst = vif.aw_burst;

      for (int i = 0; i <= item.len; i++) begin
        @(posedge vif.clk);
        while (!(vif.w_valid && vif.w_ready)) @(posedge vif.clk);
        item.data_q.push_back(vif.w_data);
        item.strb = vif.w_strb;
      end

      @(posedge vif.clk);
      while (!(vif.b_valid && vif.b_ready)) @(posedge vif.clk);
      item.resp = vif.b_resp;

      ap.write(item);
    end
  endtask

  task monitor_read();
    forever begin
      axi4_seq_item item;
      bit last;
      item = axi4_seq_item::type_id::create("item");
      item.trans_type = READ;

      @(posedge vif.clk);
      while (!(vif.ar_valid && vif.ar_ready)) @(posedge vif.clk);
      item.addr  = vif.ar_addr;
      item.id    = vif.ar_id;
      item.len   = vif.ar_len;
      item.burst = vif.ar_burst;

      last = 0;
      while (!last) begin
        @(posedge vif.clk);
        while (!(vif.r_valid && vif.r_ready)) @(posedge vif.clk);
        item.data_q.push_back(vif.r_data);
        item.resp = vif.r_resp;
        last      = vif.r_last;
      end

      ap.write(item);
    end
  endtask
endclass


//SCOREBOARD
class axi4_scoreboard extends uvm_scoreboard;
  `uvm_component_utils(axi4_scoreboard)

  uvm_analysis_imp #(axi4_seq_item, axi4_scoreboard) analysis_export;
  bit [31:0] ref_mem[bit [31:0]];

  function new(string name = "axi4_scoreboard", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    analysis_export = new("analysis_export", this);
  endfunction

  function void write(axi4_seq_item item);
    bit [31:0] beat_addr;

    if (item.trans_type == WRITE) begin
      foreach (item.data_q[i]) begin
        beat_addr = item.addr + (i * 4);
        ref_mem[beat_addr] = item.data_q[i];
      end
    end
    else begin
      foreach (item.data_q[i]) begin
        beat_addr = item.addr + (i * 4);
        if (!ref_mem.exists(beat_addr)) begin
          `uvm_error("SB", "read from addr that was never written")
        end
        else if (ref_mem[beat_addr] == item.data_q[i]) begin
          `uvm_info("SB", "PASS: beat matched", UVM_LOW)
        end
        else begin
          `uvm_error("SB", "FAIL: beat mismatch")
        end
      end
    end
  endfunction
endclass


//AGENT
class axi4_agent extends uvm_agent;
  `uvm_component_utils(axi4_agent)

  axi4_driver  driver;
  axi4_monitor monitor;
  uvm_sequencer #(axi4_seq_item) sequencer;

  function new(string name = "axi4_agent", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    driver    = axi4_driver::type_id::create("driver", this);
    monitor   = axi4_monitor::type_id::create("monitor", this);
    sequencer = uvm_sequencer#(axi4_seq_item)::type_id::create("sequencer", this);
  endfunction

  function void connect_phase(uvm_phase phase);
    super.connect_phase(phase);
    driver.seq_item_port.connect(sequencer.seq_item_export);
  endfunction
endclass


//ENVIRONMENT
class axi4_env extends uvm_env;
  `uvm_component_utils(axi4_env)

  axi4_agent      agent;
  axi4_scoreboard scoreboard;

  function new(string name = "axi4_env", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    agent      = axi4_agent::type_id::create("agent", this);
    scoreboard = axi4_scoreboard::type_id::create("scoreboard", this);
  endfunction

  function void connect_phase(uvm_phase phase);
    super.connect_phase(phase);
    agent.monitor.ap.connect(scoreboard.analysis_export);
  endfunction
endclass


//TEST
class axi4_test extends uvm_test;
  `uvm_component_utils(axi4_test)

  axi4_env env;

  function new(string name = "axi4_test", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    env = axi4_env::type_id::create("env", this);
  endfunction
  
task run_phase(uvm_phase phase);
  axi4_write_sequence write_sequence;
  axi4_read_sequence  read_sequence;

  phase.raise_objection(this);

  write_sequence = axi4_write_sequence::type_id::create("write_sequence");
  $display("T=%0t: Starting write sequence", $time);
  write_sequence.start(env.agent.sequencer);
  $display("T=%0t: Write sequence DONE", $time);

  read_sequence = axi4_read_sequence::type_id::create("read_sequence");
  $display("T=%0t: Starting read sequence", $time);
  read_sequence.start(env.agent.sequencer);
  $display("T=%0t: Read sequence DONE", $time);

  phase.drop_objection(this);
endtask
endclass


//TOP MODULE
module axi4_tb_top;
  bit clk;
  initial clk = 0;
  always #5 clk = ~clk;

  axi4_if vif(.clk(clk));

  axi4_slave DUT (
    .clk      (clk),
    .rstn     (vif.rstn),

    .aw_id    (vif.aw_id),
    .aw_addr  (vif.aw_addr),
    .aw_len   (vif.aw_len),
    .aw_size  (vif.aw_size),
    .aw_burst (vif.aw_burst),
    .aw_valid (vif.aw_valid),
    .aw_ready (vif.aw_ready),

    .w_data   (vif.w_data),
    .w_strb   (vif.w_strb),
    .w_last   (vif.w_last),
    .w_valid  (vif.w_valid),
    .w_ready  (vif.w_ready),

    .b_id     (vif.b_id),
    .b_resp   (vif.b_resp),
    .b_valid  (vif.b_valid),
    .b_ready  (vif.b_ready),

    .ar_id    (vif.ar_id),
    .ar_addr  (vif.ar_addr),
    .ar_len   (vif.ar_len),
    .ar_size  (vif.ar_size),
    .ar_burst (vif.ar_burst),
    .ar_valid (vif.ar_valid),
    .ar_ready (vif.ar_ready),

    .r_id     (vif.r_id),
    .r_data   (vif.r_data),
    .r_resp   (vif.r_resp),
    .r_last   (vif.r_last),
    .r_valid  (vif.r_valid),
    .r_ready  (vif.r_ready)
  );

  initial begin
    vif.rstn = 0;
    repeat(5) @(posedge vif.clk);
    vif.rstn = 1;
  end
  
  initial begin
  $dumpfile("dump.vcd");
  $dumpvars;
end
  
  initial begin
    #10000;
    $display("=== TIMEOUT: simulation did not finish in 10000 time units ===");
    $finish;
  end

  initial begin
    uvm_config_db#(virtual axi4_if)::set(null, "*", "vif", vif);
    run_test("axi4_test");
  end
endmodule
