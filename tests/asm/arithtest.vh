// Auto-generated SystemVerilog file with register file changes
package reg_changes_pkg;
	typedef struct packed {
	    logic [4:0] name;
	    logic [31:0] val;
	} reg_change_t;

	// Array of register changes
	reg_change_t changes[16] = '{
		'{5'd2, 32'h00000400},
		'{5'd3, 32'h00000800},
		'{5'd4, 32'h00000c00},
		'{5'd5, 32'h000004d2},
		'{5'd6, 32'h04d20000},
		'{5'd7, 32'h04d203e7},
		'{5'd8, 32'h04d1ffe7},
		'{5'd9, 32'h00000400},
		'{5'd10, 32'h000004ff},
		'{5'd11, 32'h00269000},
		'{5'd12, 32'h004d2000},
		'{5'd13, 32'h00020000},
		'{5'd14, 32'h00000040},
		'{5'd15, 32'hfffffb01},
		'{5'd16, 32'h00064000},
		'{5'd10, 32'h0000000a}
	};
endpackage
