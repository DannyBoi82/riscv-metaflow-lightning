// Auto-generated SystemVerilog file with register file changes
package reg_changes_pkg;
	typedef struct packed {
	    logic [4:0] name;
	    logic [31:0] val;
	} reg_change_t;

	// Array of register changes
	reg_change_t changes[2] = '{
		'{5'd1, 32'h00000021},
		'{5'd10, 32'h0000000a}
	};
endpackage
