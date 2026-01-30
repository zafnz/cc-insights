I want to implement worktrees. I want when the app opens it notices that the project dir is the top of a git repo, and it offers to enable worktree support, and it explains what worktrees are.

I want that one session is the "main" one, sitting on the main branch. Then by typing `/workstart <task>` it creates a new git worktree for that task, and a new session is created that is in that worktree as its project dir. 

The worktree/branch name should be in the format "cci/first-part-of-task-text" with a -1 -2 -3 added if there are conflicts. 

There will be assocaited settings with projects with worktrees, so we will implement additional config. In  ~/.ccinsights/projects.json we will store settings, like:
{
    "/tmp/cc-insights/claude-system": {
        "mainBranch": "main", // Could be master on older repos
        "worktreeEnabled": true,
        "worktreePath: "/tmp/cc-insights/claude-system-wt"
        "worktrees": {
             "cci/first-part-of-task-text": {
                  "sessionId": "1234-4445-6666666-2232",
                  "merged": false,
         }
    }
}

There will also be a /workdone command. When run inside a worktree it will first check if there are any uncommited changes, and if so warn the user. Then check the branch has been merged main . (Not sure how to reliably do that). If it has not, or it isn't sure, then it will warn the user.

Evaluate these goals. Write up a plan document in docs/features/worktrees.md, research everything needed and come up with a full implementation plan.

Ask any questions you need of me.






## Revisions
Ok, we have completed everything up to most of task 18
- docs/features/worktrees/tasks.md
- docs/features/worktrees/plan.md

Before we do implementation and E2E tests its become apparent the UI needs work.

Having us needing to start a non worktree session makes no sense.

This will require the app to slightly separate Claude sessions from session panels, in that an entry in the sessions list can exist that doesn't yet have a claude session.

### Changes:
When the app starts:
1) Checks if the current directory is in the projects config file. If not, show the welcome screen. 
2) Once the user elects to open the current directory its entry is created in the projects config.
3) Display the project opened panel in the conversation output pane.

### Welcome screen.
The welcome screen only displays if the current working directory is not in the projects config.
It shows the current working directory, and offers the user to:
- Open a project folder 
- Begin work in this folder
Future note: We need to do the trusted/untrusted check too.

### Project opened panel

When a project is opened this panel shows, it simply says:
```
Begin chatting below
Model: [Opus]

Note: you can create worktrees to work on multiple
branches at the same time without conflicting, just type /worktree
```

### Sessions panel

The sessions panel needs a rework

When not working with worktrees, it looks like this:
```
+------------------+
| <main>           |
|  * <session>     |
|  * <session>     |
|  * <session>     |
+------------------+
```
Main is the name of the git branch we are in, or if no git repo, then it is just the name of the folder.

When in worktree mode, this is the display when opening.
```
+------------------+-----------------------------+
| <main>           |                             |
| |  * <session>   |                             |
| +-<feat-1>       |                             |
| |  * <session>   |                             |
| |  * <session>   |      Project open panel     |
| +-+<feat-2>      |                             |      
| | | * <session>  |                             |      
| | +-<feat-2-a>   |                             |      
| |.  * <session>  |                             |
|                  +-----------------------------+
|                  | Start chatting.           |>|
+------------------+-----------------------------+
```
There each of the branches are actually worktrees, which can have sessions in them (typically only one)

In the above, there is the main branch, and feat-1 and feat-2 were created off the main branch. feat-2-a was created off feat-2.

The intro text is something like: To begin work on a new feature type `/worktree new <new-branch-name>`

On a brand new setup there will be just main (or whatever the git branch name is of the project dir) and one initial session

For the most part this doesn't concern claude except that each of those sessions have their CWD in the worktree path.

### Creating a worktree

When the user creates a worktree they are prompted for a feature description (if not supplied) the help text explains this is not the request, but forms the name of the git branch. If the user is creating a branch off something other than main or master then the app will warn "You are creating your branch based off [branch], are you sure you don't want to use main/master?" [Abort][Continue]

Once they have confirmed (if needed) then create a git worktree as we have already coded (`git worktree add <branch>`), and add
it to our project config. 

Then we show all the worktrees as above

The initial dialog for the new worktree session should show text explaining: When you are done with your worktree and have merged the branch into main, then you can type `/worktree finished` or rightclick the tree name to delete the worktree. 


### Deleting a worktree
When the user types `/worktree finished` or clicks the context menu, then do the standard merge check, and if they confirm, delete


### Project Configuration (`~/.ccinsights/projects.json`)

We are going to need to expand/change this config file:
```json
{
  "/tmp/cc-insights/claude-system": {
    "mainBranch": "main",
    "worktreeEnabled": true,
    "worktreePath": "/tmp/cc-insights/claude-system-wt",
    "autoSelectWorktree": true,
    "sessions": [
      {
        "sessionId": "123-456-789",
        "name": "Why is the sky blue?"
      }
    ],
    "worktrees": {
      "cci/add-dark-mode": {
        "name": "Add Dark Mode",
        "merged": false,
        "branchName": "add-dark-mode",
        "createdAt": "2025-01-24T10:30:00Z",
        "taskDescription": "Add dark mode toggle",
        "deleted": false,
        "sessions": [
          {
            "sessionId": "123-456-789",
            "name": "Add Dark Mode"
          }
        ]
      }
    }
  }
}
```
