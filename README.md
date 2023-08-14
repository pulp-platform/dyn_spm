# Dynamic Scratchpad Memory

The scratch-pad TCDM memory featured with dynamically switching address mapping policy. 

The Dynamic Scratchpad Memory has been integrated in [Carfield](https://github.com/pulp-platform/carfield) of [PULP](https://github.com/pulp-platform) Platform.

## SPEC
![Specification](/doc/figure/Spec_L2_Mem.png)
- Two AXI ports
- Supports two address mapping modes
  - interleaved
  - non-interleaved
- Uses 4 address spaces to determine which AXI port and which mapping mode
  - every address space is targeting to the same Dyn Mem space
- SRAM Banks are equipped with ECC 

## Getting started

### Prerequisites

The dynamic scratchpad memory uses [`bender`](https://github.com/pulp-platform/bender) to manage its dependencies and to automatically generate compilation scripts. Currently, we do not proviode any open-source simulation setup, instead the dynamic scratchpad memory was simulated using `Questasim`.


### Tips for instantiation

Before instantiating the dynamic scratchpad memory, make sure you have prepared these parameters
Name | Type | Description
---- | ---- | -----------
`NUM_PORT` | `int unsigned` | number of AXI ports (default 2 ports)
`AXI_ADDR_WIDTH` | `int unsigned` | AXI addr width
`AXI_DATA_WIDTH` | `int unsigned` | AXI data width
`AXI_ID_WIDTH` | `int unsigned` | AXI id width
`AXI_USER_WIDTH` | `int unsigned` | AXI user width
`axi_req_t` | `type` | AXI request type
`axi_resp_t` | `type` | AXI response type
`NUM_MAP_RULES` | `int unsigned` | number of mapping rules. defualtly we have 4 rules, namely 2 ports * 2 modes
`map_rule_t` | `type` | Please use this definition `struct packed {int unsigned idx; logic [AXI_ADDR_WIDTH-1:0] start_addr; logic [AXI_ADDR_WIDTH-1:0] end_addr;}`
`L2_MEM_SIZE_IN_BYTE` | `int unsigned` | size of Dyn Mem (in byte)
`NUM_BANK_GROUP` | `int unsigned` | number of bank groups (default 2 bank groups)

- Mapping rule
  - 4 address spaces and prepare the type `map_rule_t`, parameter `NUM_MAP_RULES`, and constant varible `mapping_rules`  like this 

![prepare address mapping](/doc/figure/addr_map_prepare.png)

### Run testbench
Please use the command `make vsim`  for running testbench


## License

All hardware sources and tool scripts are licensed under the Solderpad Hardware License 0.51
(see `LICENSE`)
