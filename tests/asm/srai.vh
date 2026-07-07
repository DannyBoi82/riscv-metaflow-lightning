// Auto-generated SystemVerilog file with register file changes
package reg_changes_pkg;
	typedef struct packed {
	    logic [4:0] name;
	    logic [31:0] val;
	} reg_change_t;

	// Array of register changes
	reg_change_t changes[9] = '{
		'{5'd2, 32'h12345000},
		'{5'd2, 32'h12345678},
		'{5'd12, 32'h80000000},
		'{5'd11, 32'h12345678},
		'{5'd13, 32'h00001234},
		'{5'd14, 32'h00000000},
		'{5'd15, 32'h002468ac},
		'{5'd16, 32'hffff8000},
		'{5'd10, 32'h0000000a}
	};
endpackage
