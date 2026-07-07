// Auto-generated SystemVerilog file with register file changes
package reg_changes_pkg;
	typedef struct packed {
	    logic [4:0] name;
	    logic [31:0] val;
	} reg_change_t;

	// Array of register changes
	reg_change_t changes[17] = '{
		'{5'd10, 32'h0000000a},
		'{5'd3, 32'h00000001},
		'{5'd4, 32'hffffffff},
		'{5'd5, 32'h00000123},
		'{5'd5, 32'h0000012a},
		'{5'd1, 32'h00400024},
		'{5'd5, 32'h0040014e},
		'{5'd5, 32'h00400157},
		'{5'd5, 32'h00400162},
		'{5'd5, 32'h004001c5},
		'{5'd5, 32'h004001ca},
		'{5'd5, 32'h00400239},
		'{5'd5, 32'h00400310},
		'{5'd1, 32'h00400060},
		'{5'd5, 32'h004004cf},
		'{5'd5, 32'h0080052f},
		'{5'd5, 32'h00800b6c}
	};
endpackage
