// Auto-generated SystemVerilog file with register file changes
package reg_changes_pkg;
	typedef struct packed {
	    logic [4:0] name;
	    logic [31:0] val;
	} reg_change_t;

	// Array of register changes
	reg_change_t changes[13] = '{
		'{5'd2, 32'h10000000},
		'{5'd11, 32'h10000000},
		'{5'd11, 32'h10000005},
		'{5'd12, 32'h00001000},
		'{5'd12, 32'h00001234},
		'{5'd13, 32'h00005000},
		'{5'd13, 32'h00005678},
		'{5'd14, 32'h00004000},
		'{5'd14, 32'h00004321},
		'{5'd15, 32'h00000123},
		'{5'd16, 32'h56781234},
		'{5'd17, 32'h01234321},
		'{5'd10, 32'h0000000a}
	};
endpackage
