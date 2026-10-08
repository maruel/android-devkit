# Refresh the agent file index and verify local shell workflows.
.PHONY: fix verify

fix:
	python3 scripts/update_agents_file_index.py

verify:
	python3 scripts/update_agents_file_index.py --check
	shellcheck -s bash scripts/*.sh scripts/*.bash
