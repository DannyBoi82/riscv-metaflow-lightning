in order of discovery 
1. scheduler: selection should happen before operand muxing instead of during
    - to not have this happen, the operand arrays need to be sized bigger than # of exec units
2. lw needs to only unlock lockers (set result.result_valid) when the data is actually there, not just the address
3. need to check if a dependency is retiring this cycle before locking an incoming locker to not stall the processor forever
4. fun fact: the byte offset of a load comes from the bottom 2 bits of its FULL address (32 bits), not the bottom 2 bits of its MEMORY address (30 bits)
5a. memtest1 and memtest2 look very similar in vscode's tabs. make sure you are looking at the right testcase idiot
5b. ssc needs to index into dris with DRIS_ENTRIES-1 bits to not include the color bit and walk off the end of the dris array.