// Auto-generated SystemVerilog file with register file changes
package reg_changes_pkg;
	typedef struct packed {
	    logic [4:0] name;
	    logic [31:0] val;
	} reg_change_t;

	// Array of register changes
	reg_change_t changes[12] = '{
		'{5'd2, 32'h10000000},
		'{5'd11, 32'h10000000},
		'{5'd11, 32'h10000005},
		'{5'd3, 32'h12350000},
		'{5'd3, 32'h1234ffff},
		'{5'd4, 32'haaaa4000},
		'{5'd4, 32'haaaa4321},
		'{5'd13, 32'hffffffff},
		'{5'd14, 32'h00001234},
		'{5'd15, 32'hffffaaaa},
		'{5'd16, 32'h00004321},
		'{5'd10, 32'h0000000a}
	};
endpackage
