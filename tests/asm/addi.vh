// Auto-generated SystemVerilog file with register file changes
package reg_changes_pkg;
	typedef struct packed {
	    logic [4:0] name;
	    logic [31:0] val;
	} reg_change_t;

	// Array of register changes
	reg_change_t changes[5] = '{
		'{5'd2, 32'h00000001},
		'{5'd2, 32'h00000005},
		'{5'd9, 32'h00000003},
		'{5'd8, 32'hfffffffa},
		'{5'd10, 32'h0000000a}
	};
endpackage
