# Dual Counter (Cycle + Batch)

A ComfyUI custom node with two nested, persistent counters, built for
cycling through a multiline list of prompts (e.g. one prompt per line fed
into a String Selector / line-picker node) and tracking how many full
passes have been generated.

## Behavior

- **counter_1** starts at `1` and increases by `1` every time the node
  runs (every Queue Prompt). Once it exceeds `max_count_1`, it resets to
  `1` and **counter_2** increases by `1`.
- **counter_2** starts at `1` and behaves the same way against its own
  `max_count_2`: once it exceeds `max_count_2`, it resets to `1`.
- Both counters persist across ComfyUI restarts (state is saved to
  `dual_counter_state.json` next to the node file), keyed per node
  ID. Different workflows with the same node ID share counter state.
- The node always re-executes on every run (via `IS_CHANGED` returning
  `NaN`), even if ComfyUI would otherwise think its inputs are unchanged
  and try to skip/cache it.

### Example with `max_count_1 = 5`, `max_count_2 = 3`

| Run | counter_1 | counter_2 |
|-----|-----------|-----------|
| 1   | 1         | 1         |
| 2   | 2         | 1         |
| 3   | 3         | 1         |
| 4   | 4         | 1         |
| 5   | 5         | 1         |
| 6   | 1         | 2         |
| 7   | 2         | 2         |
| ... | ...       | ...       |
| 16  | 1         | 1  (wraps: counter_2 hit max_count_2=3 and reset) |

## Inputs

| Name          | Type | Notes                                              |
|---------------|------|-----------------------------------------------------|
| max_count_1   | INT  | Required. Set this to the number of lines/prompts in your multiline string. |
| max_count_2   | INT  | Required. How many full passes over the list before counter_2 wraps back to 1. |
| reset         | BOOLEAN | Optional. Set to True and run once to force both counters back to 1, then set back to False. |

## Outputs

| Name              | Type | Notes |
|-------------------|------|-------|
| counter_1         | INT  | 1-indexed. Wire this into a String Selector node if it expects a 1-indexed line number. |
| counter_1_index0  | INT  | 0-indexed (`counter_1 - 1`). Wire this in instead if your String Selector node is 0-indexed. |
| counter_2         | INT  | Increments once per full pass through the list. Handy as a seed offset, filename suffix, or subfolder index. |

## Installation

1. Copy this whole `ComfyUI-DoubleCounters` folder into your ComfyUI
   `custom_nodes/` directory:
   ```bash
   cp -r ComfyUI-DoubleCounters /path/to/ComfyUI/custom_nodes/
   ```
2. Restart ComfyUI (or use "Reload Custom Nodes" if your setup supports it).
3. The node will appear under **Counters > Dual Counter (Cycle + Batch)**.

## Typical wiring

```
[Multiline String] --> [String Selector] <-- counter_1 (or counter_1_index0)
                                          |
                                          v
                                  [line -> CLIP Text Encode / prompt input]

[Dual Counter].counter_2 --> (optional) seed math / filename suffix node
```

Set `max_count_1` to the number of lines in your multiline prompt string.
Each Queue Prompt run advances to the next line automatically; once every
line has been used, counter_2 ticks up (e.g. "batch 2 of N"), and once
counter_2 itself completes `max_count_2` passes, it wraps back to 1 so the
whole cycle can repeat indefinitely.

## Resetting

If you change your prompt list or want to start over, toggle the `reset`
input to `True`, run the workflow once, then set it back to `False`.

## Git installation

```bash
cd /path/to/ComfyUI/custom_nodes
git clone https://github.com/thaw1366/ComfyUI-DoubleCounters.git
```

No extra Python packages are required. Keep this folder on persistent storage
to preserve counters when replacing a pod.
