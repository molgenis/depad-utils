# depad-utils

Utilities for deploy admins.

## 1. How to use this repo and contribute

We use a standard GitHub workflow except that we use only one branch "*master*" as this is a relatively small repo and we don't need the additional overhead from branches.
```
   ⎛¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯⎞                                               ⎛¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯⎞
   ⎜ Shared repo a.k.a. "blessed"       ⎜ <<< 7: Merge <<< pull request <<< 6: Send <<< ⎜ Your personal online fork a.k.a. "origin"        ⎜
   ⎜ github.com/molgenis/depad-utils.git⎜ >>> 1: Fork blessed repo >>>>>>>>>>>>>>>>>>>> ⎜ github.com/<your_github_account>/depad-utils.git ⎜
   ⎝____________________________________⎠                                               ⎝__________________________________________________⎠
      v                                                                                                   v      ʌ
      v                                                                       2: Clone origin to local disk      5: Push commits to origin
      v                                                                                                   v      ʌ
      v                                                                                  ⎛¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯¯⎞
      `>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> 3: pull from blessed >>> ⎜ Your personal local clone                        ⎜
                                                                                         ⎜ ~/git/depad-utils                                ⎜
                                                                                         ⎝__________________________________________________⎠
                                                                                              v                                        ʌ
                                                                                              `>>> 4: Commit changes to local clone >>>´
```

 1. Fork this repo on GitHub (Once).
 2. Clone to your local computer and setup remotes (Once).
   ```
   #
   # Clone repo
   #
   git clone https://github.com/your_github_account/depad-utils.git
   #
   # Add blessed remote (the source of the source) and prevent direct push.
   #
   cd depad-utils
   git remote add            blessed https://github.com/molgenis/depad-utils.git
   git remote set-url --push blessed push.disabled
   ```
   
 3. Pull from "*blessed*" (Regularly from 3 onwards).
   ```
   #
   # Pull from blessed master.
   #
   cd depad-utils
   git pull blessed master
   ```
   Make changes: edit, add, delete...

 4. Commit changes to local clone.
   ```
   #
   # Commit changes.
   #
   git status
   git add some/changed/files
   git commit -m 'Describe your changes in a commit message.'
   ```
   
 5. Push commits to "*origin*".
   ```
   #
   # Push commits.
   #
   git push origin master
   ```

 6. Go to your fork on GitHub and create a pull request.
 
 7. Have one of the other team members review and eventually merge your pull request.
 
 3. Back to 3 to pull from "*blessed*" to get your local clone in sync.
   ```
   #
   # Pull from blessed master.
   #
   cd depad-utils
   git pull blessed master
   ```
   etc.

## 2. Main sections / topics

```
    depad-utils/
    `-- bin/: various scripts to manage deployment of software modules.
```