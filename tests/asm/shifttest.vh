// Auto-generated SystemVerilog file with register file changes
package reg_changes_pkg;
	typedef struct packed {
	    logic [4:0] name;
	    logic [31:0] val;
	} reg_change_t;

	// Array of register changes
	reg_change_t changes[8] = '{
		'{5'd3, 32'hfffffbed},
		'{5'd4, 32'h7da00000},
		'{5'd5, 32'hfffefb40},
		'{5'd6, 32'h001f6800},
		'{5'd7, 32'hfffffffe},
		'{5'd8, 32'h001f6800},
		'{5'd9, 32'h0000fffe},
		'{5'd10, 32'h0000000a}
	};
endpackage
