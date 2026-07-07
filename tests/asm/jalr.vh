// Auto-generated SystemVerilog file with register file changes
package reg_changes_pkg;
	typedef struct packed {
	    logic [4:0] name;
	    logic [31:0] val;
	} reg_change_t;

	// Array of register changes
	reg_change_t changes[8] = '{
		'{5'd8, 32'h00400000},
		'{5'd8, 32'h0040001c},
		'{5'd9, 32'h00400000},
		'{5'd2, 32'h00400000},
		'{5'd2, 32'h00400024},
		'{5'd20, 32'h00400018},
		'{5'd22, 32'h00400020},
		'{5'd10, 32'h0000000a}
	};
endpackage
