// Auto-generated SystemVerilog file with register file changes
package reg_changes_pkg;
	typedef struct packed {
	    logic [4:0] name;
	    logic [31:0] val;
	} reg_change_t;

	// Array of register changes
	reg_change_t changes[22] = '{
		'{5'd8, 32'h00010000},
		'{5'd8, 32'h0000ff00},
		'{5'd9, 32'h000000ff},
		'{5'd11, 32'h00010000},
		'{5'd11, 32'h0000ff00},
		'{5'd12, 32'h00010000},
		'{5'd12, 32'h0000ff00},
		'{5'd14, 32'hff000000},
		'{5'd15, 32'h00ff0000},
		'{5'd17, 32'hffff0000},
		'{5'd18, 32'hffff0000},
		'{5'd20, 32'h12341000},
		'{5'd20, 32'h12341234},
		'{5'd21, 32'h12341000},
		'{5'd21, 32'h12341234},
		'{5'd2, 32'h00000000},
		'{5'd13, 32'h0000ff00},
		'{5'd16, 32'h00000000},
		'{5'd19, 32'hffff0000},
		'{5'd22, 32'h12341234},
		'{5'd25, 32'h00000000},
		'{5'd10, 32'h0000000a}
	};
endpackage
