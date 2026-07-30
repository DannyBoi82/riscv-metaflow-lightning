1. request processing acknoweleged signal for writes to make retiring sws more straghtforward and make memory ops pipelinable
2. nonblocking
3. parameterizable number of outstanding requests
4. seperate read and write ports
5. multiple addresses servicable at once (2 different read, a 3rd write, all to diff blocks)
