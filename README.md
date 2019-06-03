# depad-utils

Utilities for deploy admins.

## 1. List of tools.

### Repo layout.

```
    depad-utils/
    |-- bin/: various scripts to manage deployment of software modules.
    |-- .gitignore
    |-- LICENSE
    `-- README.md
```

### Tools.

- [hpc-environment-sync.bash](#-hpc-environment-syncbash): Synchronize deployed software, modules and reference data from primary to a secondary location.
- [generateEasyConfig.R](#-generateeasyconfigr): Helper script for making EasyConfigs for Bundles of R packages.
- [GetPerlModuleDepTreeFromCPAN.pl](#-getperlmodulepeptreefromcpanpl): Helper script for making EasyConfigs for Bundles of Perl modules.

#### <a name="hpc-environment-syncbash"/> hpc-environment-sync.bash

Use the ```hpc-environment-sync.cfg``` config file in the same location as the script to configure various defaults.

```
Usage:

   hpc-environment-sync.bash [-l] -a
   hpc-environment-sync.bash [-l] -r relative/path/to/ReferenceData/
   hpc-environment-sync.bash [-l] -m ModuleName/ModuleVersion

Details:

 -l   List: Do not perform actual sync, but only list changes instead (dry-run).

 -a   All: syncs complete HPC environment (software, modules & reference data) from /apps/.

 -r   Reference data: syncs only the specified data.
      Path may be either an absolute path or relative to ${SOURCE_ROOT_PATH}/${REFDATA_DIR_NAME} as specified in hpc-environment-sync.cfg.

 -m   Module: syncs only the specified module.
      The tool must have been deployed with EasyBuild, with accompanying "module" file 
      and specified using NAME/VERSION as per "module" command syntax.
      Will search for modules in ${SOURCE_ROOT_PATH}/${MODULES_DIR_NAME}  as specified in hpc-environment-sync.cfg.
      for software installed in  ${SOURCE_ROOT_PATH}/${SOFTWARE_DIR_NAME} as specified in hpc-environment-sync.cfg.
      The special NAME/VERSION combination ANY/ANY will sync all modules.
```

#### <a name="generateeasyconfigr"/> generateEasyConfig.R

```
Description: 
    Generates an EasyBuild EasyConfig file from an existing R environment.
    Optionally you can first load a specific version of R using module load before generating the *.eb EasyConfig

Example usage:
    module load EasyBuild
    module load R
    generateEasyConfig.R  --tc  foss/2018b \
                          --od  /path/to/my/EasyConfigs/r/R/ \
                          --ll  WARNING 

Explanation of options:
    --tc toolchain/version  EasyBuild ToolChain (required).
                               To get a list of available toolchains (may or may not be already installed):
                                   module load EasyBuild
                                   eb --list-toolchains
                               To check if a toolchain is already installed and if yes which version is the default:
                                   module -r -t avail -d '^name_of_toolchain$'
    --od path               Output Directory where the generated *.eb EasyConfig file will be stored (optional).
                               Will default to the current working directory as determined with getwd().
                               Name of the output file follows strict rules 
                               and is automatically generated based on R version and toolchain.
    --ll LEVEL              Log level (optional).
                               One of FINEST, FINER, FINE, DEBUG, INFO (default), WARNING, ERROR or CRITICAL.
```

#### <a name="getperlmodulepeptreefromcpanpl"/> GetPerlModuleDepTreeFromCPAN.pl

```
Usage:

   GetPerlModuleDepTreeFromCPAN.pl options

Available options are:

   -pm '[PM]'    Quoted and space sperated list of Perl Modules. E.g. 'My::SPPACE::Seperated List::Of::Modules'
   -of [format]  Output Format. One of: list or eb ("exts_list" format for including in an EasyBuild Bundle easyconfig.")
   -ll [LEVEL]   Log4perl Log Level. One of: ALL, TRACE, DEBUG, INFO (default), WARN, ERROR, FATAL or OFF.
```

## 2. How to use this repo and contribute

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
