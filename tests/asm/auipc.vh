// Auto-generated SystemVerilog file with register file changes
package reg_changes_pkg;
	typedef struct packed {
	    logic [4:0] name;
	    logic [31:0] val;
	} reg_change_t;

	// Array of register changes
	reg_change_t changes[8] = '{
		'{5'd3, 32'h803ff000},
		'{5'd4, 32'h00400004},
		'{5'd5, 32'h80400008},
		'{5'd6, 32'h003ff00c},
		'{5'd20, 32'h00404010},
		'{5'd21, 32'h00404014},
		'{5'd22, 32'h013ff018},
		'{5'd10, 32'h0000000a}
	};
endpackage
