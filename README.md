# SimpleBudget

A SwiftUI-based personal budgeting app with iCloud-backed data and lock-screen/home-screen widgets for quick expense capture.

## Repository basics
- The `SimpleBudget` target contains the main app code.
- The `BudgetWidget` target provides the lock-screen/home-screen widget and `AppIntent` for quick-add expenses.

## How to commit your changes
Run these commands in a local shell (not in chat):

1. Check what changed:
   ```bash
   git status -sb
   ```
2. Stage the files you want to commit (all files or specific paths):
   ```bash
   git add .
   # or: git add path/to/file.swift
   ```
3. Create a commit with a short description:
   ```bash
   git commit -m "Describe your change"
   ```
4. Push to your branch (replace `branch` if needed):
   ```bash
   git push        # pushes the current branch
   # git push origin your-branch-name
   ```

If you need to edit the last commit before pushing, use:
```bash
git commit --amend
```
Then push with:
```bash
git push --force-with-lease
```

> Tip: You don’t need to paste these commands into chat—run them in your terminal where the repository is checked out.
