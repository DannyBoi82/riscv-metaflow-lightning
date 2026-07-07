// Auto-generated SystemVerilog file with register file changes
package reg_changes_pkg;
	typedef struct packed {
	    logic [4:0] name;
	    logic [31:0] val;
	} reg_change_t;

	// Array of register changes
	reg_change_t changes[7] = '{
		'{5'd5, 32'h0000000a},
		'{5'd6, 32'h00000005},
		'{5'd7, 32'h00000136},
		'{5'd28, 32'h000001f4},
		'{5'd29, 32'h00000216},
		'{5'd29, 32'h00000243},
		'{5'd10, 32'h0000000a}
	};
endpackage
