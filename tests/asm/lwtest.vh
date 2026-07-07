// Auto-generated SystemVerilog file with register file changes
package reg_changes_pkg;
	typedef struct packed {
	    logic [4:0] name;
	    logic [31:0] val;
	} reg_change_t;

	// Array of register changes
	reg_change_t changes[15] = '{
		'{5'd1, 32'h10000000},
		'{5'd5, 32'h000000ff},
		'{5'd6, 32'h000001fe},
		'{5'd7, 32'h000003fc},
		'{5'd8, 32'h00000bcc},
		'{5'd1, 32'h10000010},
		'{5'd16, 32'hfffffff5},
		'{5'd17, 32'hfffffff4},
		'{5'd18, 32'hfffffff3},
		'{5'd19, 32'hfffffff2},
		'{5'd20, 32'hfffffffc},
		'{5'd21, 32'hfffffffd},
		'{5'd22, 32'hfffffffe},
		'{5'd23, 32'hffffffff},
		'{5'd10, 32'h0000000a}
	};
endpackage
