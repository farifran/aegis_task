import json
import glob
from pathlib import Path

# Paths to search
golden_paths = glob.glob("tests/golden/*/golden_discovery.json")

for path_str in golden_paths:
    path = Path(path_str)
    if not path.exists():
        continue
    
    print(f"Pruning {path}...")
    with open(path, "r") as f:
        data = json.load(f)
    
    snapshot = data.get("artifact_snapshot", {})
    op_ctx = snapshot.get("operational_context", {})
    
    # Fields to preserve
    to_keep = ["investigation_scope", "blocking_conditions", "attention_targets"]
    
    pruned_op_ctx = {}
    for field in to_keep:
        if field in op_ctx:
            pruned_op_ctx[field] = op_ctx[field]
        else:
            if field == "blocking_conditions" or field == "attention_targets":
                pruned_op_ctx[field] = []
            elif field == "investigation_scope":
                pruned_op_ctx[field] = {
                    "scope_type": "none",
                    "scope_targets": [],
                    "scope_confidence": "none"
                }
    
    snapshot["operational_context"] = pruned_op_ctx
    
    with open(path, "w") as f:
        json.dump(data, f, indent=2)
        f.write("\n")

print("Migration completed successfully.")
