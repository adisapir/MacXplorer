# Repository Instructions

## Git

- Do not auto commit
- Do not read or modify todo.txt
- Display every git command in chat before running it.
- Suggest missing git steps that follow best practices, calibrated for a single-contributor repository.
- Before merging a branch into `main`, do the following: 
    - increment the app version by `0.01` unless the developer specifies otherwise, commit that version change as the final branch commit, and then merge.
    - Ask the developer whether: 
        - 1. They want to update `CHANGELOG.md`
        - 2. Let the agent suggest updated to `CHANGELOG.md`. 
        - 3. Don't modify `CHANGELOG.md` 
        - If option 2 is selected, let the user review/edit/approve the Agent's suggestion
        - Wait for use input before merging.
    - Run generate-oui-vendors.py
    - Run build-distribution.sh as last step
- Don't add "Co-Authored-By: " signatures (Agent generated) to commits, MRs
