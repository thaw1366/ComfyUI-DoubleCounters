import json
import os

# Persistent storage so counters survive ComfyUI restarts (e.g. RunPod pod
# restarts). State is keyed by each node instance's unique_id so multiple
# Dual Counter nodes in the same or different workflows don't collide.
_STATE_FILE = os.path.join(os.path.dirname(__file__), "dual_counter_state.json")


def _load_state():
    if os.path.exists(_STATE_FILE):
        try:
            with open(_STATE_FILE, "r") as f:
                return json.load(f)
        except Exception:
            return {}
    return {}


def _save_state(state):
    try:
        with open(_STATE_FILE, "w") as f:
            json.dump(state, f)
    except Exception as e:
        print(f"[DualCounter] Failed to save state: {e}")


_state = _load_state()


class DualCounter:
    """
    Two nested counters for cycling through a multiline prompt list.

    counter_1 increments by 1 on every run, starting at 1. When it exceeds
    `max_count_1`, it wraps back to 1 and counter_2 increments by 1.
    counter_2 behaves the same way against its own `max_count_2`: once it
    exceeds that max, it wraps back to 1 too.

    Typical use: feed counter_1 (or counter_1_index0) into a String
    Selector / line-picker node to walk through a multiline prompt string
    line by line. counter_2 then tracks how many full passes over the list
    have completed -- e.g. use it as a seed offset, subfolder index, or
    filename suffix -- and itself wraps after max_count_2 passes.
    """

    CATEGORY = "Counters"
    FUNCTION = "run"
    RETURN_TYPES = ("INT", "INT", "INT")
    RETURN_NAMES = ("counter_1", "counter_1_index0", "counter_2")
    OUTPUT_NODE = False

    @classmethod
    def INPUT_TYPES(cls):
        return {
            "required": {
                "max_count_1": ("INT", {"default": 10, "min": 1, "max": 100000, "step": 1}),
                "max_count_2": ("INT", {"default": 10, "min": 1, "max": 100000, "step": 1}),
            },
            "optional": {
                "reset": ("BOOLEAN", {"default": False}),
            },
            "hidden": {
                "unique_id": "UNIQUE_ID",
            },
        }

    def run(self, max_count_1, max_count_2, reset=False, unique_id=None):
        key = str(unique_id) if unique_id is not None else "default"
        node_state = _state.get(key, {"counter_1": 0, "counter_2": 1})

        if reset:
            node_state = {"counter_1": 0, "counter_2": 1}

        # advance counter_1
        node_state["counter_1"] += 1

        if node_state["counter_1"] > max_count_1:
            node_state["counter_1"] = 1
            # advance counter_2 since counter_1 completed a full cycle
            node_state["counter_2"] += 1

            if node_state["counter_2"] > max_count_2:
                node_state["counter_2"] = 1

        _state[key] = node_state
        _save_state(_state)

        counter_1 = node_state["counter_1"]
        counter_2 = node_state["counter_2"]
        return (counter_1, counter_1 - 1, counter_2)

    @classmethod
    def IS_CHANGED(cls, max_count_1, max_count_2, reset=False, unique_id=None):
        # NaN never equals itself, so ComfyUI always treats this node as
        # changed and re-executes it every queue run, even though its
        # declared inputs may be identical to the previous run.
        return float("nan")


class PromptImageCounter:
    """
    Compatibility node used by the attached workflow. It emits an image index
    for each image made per prompt and a zero-based prompt index.
    """

    CATEGORY = "Counters"
    FUNCTION = "run"
    RETURN_TYPES = ("INT", "INT")
    RETURN_NAMES = ("image_number", "prompt_number")
    OUTPUT_NODE = False

    @classmethod
    def INPUT_TYPES(cls):
        return {
            "required": {
                "images_per_prompt": ("INT", {"default": 1, "min": 1, "max": 100000, "step": 1}),
                "image_start": ("INT", {"default": 1, "min": 0, "max": 1000000, "step": 1}),
                "num_prompts": ("INT", {"default": 1, "min": 1, "max": 100000, "step": 1}),
                "prompt_start": ("INT", {"default": 0, "min": 0, "max": 1000000, "step": 1}),
                "reset": ("BOOLEAN", {"default": False}),
            },
            "hidden": {
                "unique_id": "UNIQUE_ID",
            },
        }

    def run(self, images_per_prompt, image_start, num_prompts, prompt_start, reset=False, unique_id=None):
        images_per_prompt = max(1, int(images_per_prompt))
        num_prompts = max(1, int(num_prompts))
        image_start = int(image_start)
        prompt_start = int(prompt_start)
        key = f"PromptImageCounter:{unique_id if unique_id is not None else 'default'}"

        if reset:
            current_image = image_start
            current_prompt = prompt_start
        else:
            state = _state.get(key, {})
            current_image = int(state.get("image_number", image_start))
            current_prompt = int(state.get("prompt_number", prompt_start))
            current_image = image_start + ((current_image - image_start) % images_per_prompt)
            current_prompt = prompt_start + ((current_prompt - prompt_start) % num_prompts)

        next_image = current_image + 1
        next_prompt = current_prompt
        if next_image >= image_start + images_per_prompt:
            next_image = image_start
            next_prompt += 1
            if next_prompt >= prompt_start + num_prompts:
                next_prompt = prompt_start

        _state[key] = {"image_number": next_image, "prompt_number": next_prompt}
        _save_state(_state)
        return (current_image, current_prompt)

    @classmethod
    def IS_CHANGED(cls, images_per_prompt, image_start, num_prompts, prompt_start, reset=False, unique_id=None):
        return float("nan")


NODE_CLASS_MAPPINGS = {
    "DualCounter": DualCounter,
    "PromptImageCounter": PromptImageCounter,
}

NODE_DISPLAY_NAME_MAPPINGS = {
    "DualCounter": "Dual Counter (Cycle + Batch)",
}
