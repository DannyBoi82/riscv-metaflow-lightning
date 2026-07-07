// Auto-generated SystemVerilog file with register file changes
package reg_changes_pkg;
	typedef struct packed {
	    logic [4:0] name;
	    logic [31:0] val;
	} reg_change_t;

	// Array of register changes
	reg_change_t changes[7] = '{
		'{5'd8, 32'h00010000},
		'{5'd8, 32'h0000ff00},
		'{5'd9, 32'h000000ff},
		'{5'd11, 32'h00010000},
		'{5'd11, 32'h0000ff00},
		'{5'd1, 32'hfffffffd},
		'{5'd10, 32'h0000000a}
	};
endpackage
