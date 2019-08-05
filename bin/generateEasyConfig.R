#!/usr/bin/env Rscript

#
# ToDo 1: Resolve (updated) verions of dependencies
# ToDo 2: Inject checksums for source tarballs into EasyConfigs 
#         for both R itself as well as for additional R packages.
#

#
# Hard-coded list of R package repositories.
#
#  * Active URLs are used for checking if a package may have been retrieved from that repo.
#  * Archive URLs cannot be used by R commands to query the repo, 
#    but will be added to the EasyConfig and may be used by EasyBuild to download packages.
#
repos = list()
repos$cran$active = c('http://cran.r-project.org/src/contrib/')
repos$cran$archive = c('http://cran.r-project.org/src/contrib/Archive/%(name)s')
repos$bioconductor$active = c('http://www.bioconductor.org/packages/release/bioc/src/contrib/',
    'http://www.bioconductor.org/packages/release/data/annotation/src/contrib/',
    'http://www.bioconductor.org/packages/release/data/experiment/src/contrib/',
    'http://www.bioconductor.org/packages/release/extra/src/contrib/')

#
# Default versions for dependecies.
#  * This list is for R 3.6.x with foss 2018b.
#  * When different versions of these dependencies are loaded in the environment with
#        module load dependency/version
#    before this script is executed,
#    then this script will pickup the new versions from the environment overruling the defaults.
#    Extra dependencies will not get added automagically though:
#    You will need to add those
#      1. here as well as
#      2. in the functions that write the EasyConfig files.
#
dependency_defaults <-list(
    'pkg-config'='0.29.2',
    'libreadline'='8.0',
    'ncurses'='6.1',
    'bzip2'='1.0.6',
    'XZ'='5.2.4',
    'zlib'='1.2.11',
    'SQLite'='3.29.0',
    'PCRE'='8.43',
    'Java'='11.0.2',
    'cURL'='7.63.0',
    'libxml2'='2.9.8',
    'libpng'='1.6.37',
    'libjpeg-turbo'='2.0.2',
    'LibTIFF'='4.0.10',
    'cairo'='1.16.0',
    'Pango'='1.43.0',
    'GMP'='6.1.2',
    'UDUNITS'='2.2.27.6',
    'ImageMagick'='7.0.8-56',
    'MariaDB-connector-c'='3.1.2',
    'NLopt'='2.6.1'
)

#
##
### Setup environment
##
#
suppressPackageStartupMessages(library(stringr))
suppressPackageStartupMessages(library(logging))
logging::basicConfig()

#
##
### Custom functions
##
#
usage <- function() {
    cat("
Description: 
    Generates an EasyBuild EasyConfig file from an existing R environment.
    Optionally you can first load a specific version of R using module load before generating the *.eb EasyConfig

Example usage:
    module load EasyBuild
    module load R
    module load dependency/updated_version
    generateEasyConfig.R  --tc  foss/2018b \\
                          --vs  19.07.1 \\
                          --od  /path/to/my/EasyConfigs/r/R/ \\
                          --ll  WARNING 

Explanation of options:
    --tc toolchain/version  EasyBuild ToolChain (required).
                               To get a list of available toolchains (may or may not be already installed):
                                   module load EasyBuild
                                   eb --list-toolchains
                               To check if a toolchain is already installed and if yes which version is the default:
                                   module -r -t avail -d '^name_of_toolchain$'
    --vs YY.MM.release      Version suffix for RPlus bundle with additional R packages (required).
                               YY = year
                               MM = month
                               release = incremental release number of an RPlus bundle in a given YY.MM.
                                         Hence this is not a day! First release in given year and month is always 1.
    --od path               Output Directory where the generated *.eb EasyConfig file will be stored (optional).
                               Will default to the current working directory as determined with getwd().
                               Name of the output file follows strict rules 
                               and is automatically generated based on R version and toolchain.
    --ll LEVEL              Log level (optional).
                               One of FINEST, FINER, FINE, DEBUG, INFO (default), WARNING, ERROR or CRITICAL.
")
    q()
}

getDepModuleVersion <- function(dep.name, toolchain.name) {
    #
    # Get version of a loaded dependency from module command.
    #
    dep.version <- system2('module', args = c('--terse', 'list', dep.name), stdout = TRUE)
    if (is.na(dep.version) || length(dep.version) == 0) {
        dep.version <- dependency_defaults[[dep.name]]
    } else {
        #
        # Strip module name and a slash forward from the beginning of the string and
        # toolchain, toolchain version and optional version suffix from the end.
        # E.g. for cairo the STDOUT of the module list --terse command is: "cairo/1.16.0-GCCcore-7.3.0"
        # but we want only the version number of cairo: 1.16.0
        # Also check for minimal toolchains like 'GCC' and 'GCCcore' commonly used for dependencies,
        # when the toolchain used for R may be a more full featured one like 'foss'.
        #
        dep.version <- str_replace_all(dep.version , paste('^', dep.name, '/', sep=''), '')
        dep.version <- str_replace_all(dep.version , paste('-(', toolchain.name, '|GCC).*$', sep=''), '')
    }
    return(dep.version)
}

#
# For a list of R packages:
#  * Retrieve from a working R installation the package versions
#  * Re-order the packages based on their dependencies based on "Depends", "LinkingTo" and "Imports"
#  * Try to figure out which repo (or mirror) the package originated from using a list of known repos. 
#
# Arguments:
#  * packages: A vector with package names (i.e. c('ggplot2', 'RMySQL', 'stringer'))
#  * repos:    One or more repositories used by packageStatus() to retrieve information on available packages.
#
getPackageTree <- function(packages, repos) {
    
    #
    # Local helper function to extract plain package names 
    # from "Depends", "LinkingTo" and "Imports" statements like for example:
    #    Depends: R (≥ 3.0.2)
    #    Imports: evaluate (≥ 0.6), digest, formatR, highr, markdown, stringr (≥ 0.6), yaml (≥ 2.1.5), tools
    #
    getNamesOnly <- function(string) {
        messyPackages <- strsplit(string, ',\\s*', perl=TRUE)
        packageNames <- lapply(messyPackages[[1]], function(x) {return(strsplit(x, '[\\s(]', perl=TRUE)[[1]][1])})
        return(unlist(packageNames))
    }
    
    #
    # Local helper function to extract repo name from one of the repo URLs.
    getRepoName = function(repo.url) {
        repo.name = str_match(repo.url, '(cran)|(bioconductor)')[[1]][1]
        return(repo.name)
    }
    
    #
    # Local helper function to recursively retrieve a list of all dependencies for a given R package.
    #
    # Arguments:
    #  * packageName:            Name of a single package.
    #  * packageStatusOverview:  The object returned by packageStatus()
    # Returns:
    #  * packageTree:            Character vector with package names, their versions and the repo in which the package was found.
    
    getDependencies <- function (packageName, packageStatusOverview) {
        
        packageIndex <- match(packageName, names(packageStatusOverview$inst$Package))
        if (is.na(packageIndex)) {
            #logging::levellog(loglevels[['FATAL']], paste('Package', packageName, 'is not installed. Aborting!'))
            #usage()
            logging::levellog(loglevels[['WARNING']], paste('Package', packageName, 'is not installed!'))
            return()
        }
        
        dependencies <- c(getNamesOnly(packageStatusOverview$inst$Depends[packageIndex]),
                          getNamesOnly(packageStatusOverview$inst$Imports[packageIndex]),
                          getNamesOnly(packageStatusOverview$inst$LinkingTo[packageIndex]))
        dependencies <- dependencies[!is.na(dependencies)]
        
        logging::levellog(loglevels[['FINE']], paste('Package name:', packageName))
        logging::levellog(loglevels[['FINE']], paste('Dependencies:', paste(dependencies, collapse=', ')))
        logging::levellog(loglevels[['FINE']], '-----------------------------------------------')
        
        # don't need the base packages
        packageID <- match(dependencies, packageStatusOverview$inst$Package)
        isBase <- packageStatusOverview$inst$Priority[packageID] == 'base'
        isBase[is.na(isBase)] <- FALSE
        
        # take out 'R'
        cleanDeps <- dependencies[!isBase & dependencies != 'R']
        
        # let's recurse 
        if (length(cleanDeps) == 0) {
            # no more dependencies. We terminate returning package name
            return(packageName)
        } else {
            # recurse
            deps <- unlist(lapply(cleanDeps, getDependencies, packageStatusOverview))
            allDeps <- unique(c(deps, packageName))
            return(allDeps)
        }
    }
    
    logging::levellog(loglevels[['DEBUG']], 'Retrieving status overview of all installed packages...')
    
    #
    # Change available_packages_filters.
    #
    # Default: options(available_packages_filters = c("R_version", "OS_type", "subarch", "duplicates"))
    # This will fail to report packages when
    #  * They have been updated in the repo's after they were installed locally 
    #  * and the updated version of the packages has a dependency on a more recent R version.
    # The older version of the package as installed locally may still be available from a sub folder of the repo
    # like for example http://cran.r-project.org/src/contrib/Archive/... 
    # but these archive folders lack a PACKAGES.gz file, 
    # which is required for packageStatus() to figure out what is available.
    #
    #options(available_packages_filters = c("OS_type", "duplicates"))
    #
    # For some silly reason the options() above no longer work for some CRAN packages as of R 3.4.x.
    # E.g. nlme and foreign are no longer listed as "installed" from CRAN unless all filters are disabled with:
    options(available_packages_filters = NULL)
    
    #
    # Get status of all packages (installed and available) and append column for repo.
    #
    flattenedNames <- names(unlist(repos, recursive = FALSE, use.names = TRUE))
    activeRepoURLs <- unlist(subset(unlist(repos, recursive = FALSE, use.names = TRUE), grepl('.active', flattenedNames)), use.names=FALSE)
    packageStatusOverview <- packageStatus(repositories = activeRepoURLs)
    packageStatusOverview$inst$Repo <- rep(NA, nrow(packageStatusOverview$inst))
    logging::levellog(loglevels[['DEBUG']], 'Trying to figure out which repo(s) the installed package originated from...')
    
    for (this.package in rownames(packageStatusOverview$inst)) {
        logging::levellog(loglevels[['DEBUG']], paste('This package name:', this.package))
        isBase <- packageStatusOverview$inst$Priority[this.package] == 'base'
        isBase[is.na(isBase)] <- FALSE
        if (isBase) {
            packageStatusOverview$inst[this.package,]$Repo = 'base'
        } else {
            for (this.repo in names(summary(packageStatusOverview)$Repos)) {
                logging::levellog(loglevels[['FINEST']], paste(':       repo URL:', this.repo))
                logging::levellog(loglevels[['FINEST']], paste(':          names:', paste(names(summary(packageStatusOverview)$Repos[[this.repo]]), collapse=', ')))
                packages.installed_from_this_repo = as.list(summary(packageStatusOverview)$Repos[[this.repo]])$installed
                if (is.element(this.package, packages.installed_from_this_repo)) {
                    logging::levellog(loglevels[['FINE']], paste(':     found pkg in:', this.repo))
                    packageStatusOverview$inst[this.package,]$Repo = getRepoName(this.repo)
                }
            }
        }
        logging::levellog(loglevels[['DEBUG']], paste(':            repo:', packageStatusOverview$inst[this.package,]$Repo))
    }
    
    #
    # Recursively find installed packages and their dependencies (Names only).
    #
    allPackages.names <- unique(unlist(lapply(packages, getDependencies, packageStatusOverview)))
    allPackages.IDs = match(allPackages.names, packageStatusOverview$inst$Package)
    
    #
    # Report packages.
    #
    colsOfInterest <- c("Package", "Version", "Repo")
    colIDs <- match(colsOfInterest, names(packageStatusOverview$inst))
    allPackages.df <- packageStatusOverview$inst[allPackages.IDs, colIDs]
    
    return(allPackages.df)
}

#
# Compile R bare EasyConfig and write to file.
#
writeECR <- function (fh, version, deps, packages, repos, toolchain.name, toolchain.version) {
    writeLines("#", fh)
    writeLines("# This EasyBuild config file for R 'bare' was generated with generateEasyConfig.R", fh)
    writeLines("#", fh)
    writeLines("name = 'R'", fh)
    writeLines(paste("version = '", version, "'", sep=''), fh)
    writeLines("versionsuffix = '-bare'", fh)
    writeLines("homepage = 'http://www.r-project.org/'", fh)
    writeLines('description = """R is a free software environment for statistical computing and graphics."""', fh)
    writeLines("moduleclass = 'lang'", fh)
    writeLines(paste("toolchain = {'name': '", toolchain.name, "', 'version': '", toolchain.version, "'}", sep=''), fh)
    writeLines("sources = [SOURCE_TAR_GZ]", fh)
    writeLines("source_urls = ['http://cran.us.r-project.org/src/base/R-%(version_major)s']", fh)
    writeLines("", fh)
    writeLines("#", fh)
    writeLines("# Specify that at least EasyBuild v3.5.0 is required,", fh)
    writeLines("# since we rely on the updated easyblock for R to configure correctly w.r.t. BLAS/LAPACK.", fh)
    writeLines("#", fh)
    writeLines("easybuild_version = '3.5.0'", fh)
    writeLines("", fh)
    writeLines("builddependencies = [", fh)
    writeLines(paste("    ('pkg-config', '",    deps[['pkg-config']],    "'),",           sep=''), fh)
    writeLines("]", fh)
    writeLines("", fh)
    writeLines("dependencies = [", fh)
    writeLines(paste("    ('libreadline', '",   deps[['libreadline']],   "'),",           sep=''), fh)
    writeLines(paste("    ('ncurses', '",       deps[['ncurses']],       "'),",           sep=''), fh)
    writeLines(paste("    ('bzip2', '",         deps[['bzip2']],         "'),",           sep=''), fh)
    writeLines(paste("    ('XZ', '",            deps[['XZ']],            "'),",           sep=''), fh)
    writeLines(paste("    ('zlib', '",          deps[['zlib']],          "'),",           sep=''), fh)
    writeLines(paste("    ('SQLite', '",        deps[['SQLite']],        "'),",           sep=''), fh)
    writeLines(paste("    ('PCRE', '",          deps[['PCRE']],          "'),",           sep=''), fh)
    writeLines(paste("    ('Java', '",          deps[['Java']],          "', '', True),", sep=''), fh)
    writeLines(paste("    ('cURL', '",          deps[['cURL']],          "'),",           sep=''), fh)
    writeLines(paste("    ('libxml2', '",       deps[['libxml2']],       "'),",           sep=''), fh)
    writeLines(paste("    ('libpng', '",        deps[['libpng']],        "'),",           sep=''), fh)
    writeLines(paste("    ('libjpeg-turbo', '", deps[['libjpeg-turbo']], "'),",           sep=''), fh)
    writeLines(paste("    ('LibTIFF', '",       deps[['LibTIFF']],       "'),",           sep=''), fh)
    writeLines(paste("    ('cairo', '",         deps[['cairo']],         "'),",           sep=''), fh)
    writeLines(paste("    ('Pango', '",         deps[['Pango']],         "'),",           sep=''), fh)
    writeLines("    #", fh)
    writeLines("    # Disabled TK, because the -no-X11 option does not work and still requires X11,", fh)
    writeLines("    # which does not exist on headless compute nodes.", fh)
    writeLines("    #", fh)
    writeLines("    #('Tk', '8.6.9', '-no-X11'),", fh)
    writeLines("    #", fh)
    writeLines("    # OS dependency should be preferred if the os version is more recent then this version,", fh)
    writeLines("    # it's nice to have an up to date openssl for security reasons.", fh)
    writeLines("    #", fh)
    writeLines("    #('OpenSSL', '1.0.2k'),", fh)
    writeLines("]", fh)
    writeLines("", fh)
    writeLines("osdependencies = [('openssl-devel', 'libssl-dev', 'libopenssl-devel')]", fh)
    writeLines("", fh)
    writeLines("configopts = '--with-pic --enable-threads --enable-R-shlib'", fh)
    writeLines("#", fh)
    writeLines("# Bare R version. Additional packages go into RPlus.", fh)
    writeLines("#", fh)
    writeLines("configopts += ' --with-recommended-packages=no'", fh)
    writeLines("#", fh)
    writeLines("# Disable X11: prevent picking this up automagically:", fh)
    writeLines("# it may be present on the build server, but don't rely on X11 related stuff being available on compute nodes!", fh)
    writeLines("# Compiling with X11 support may result in an R that crashes on compute nodes.", fh)
    writeLines("#", fh)
    writeLines("configopts += ' --with-x=no --with-tcltk=no'", fh)
    writeLines("", fh)
    writeLines("#", fh)
    writeLines("# R package list.", fh)
    writeLines("# Only default a.k.a. base packages are listed here just for sanity checking.", fh)
    writeLines("# Additional packages go into RPlus module.", fh)
    writeLines("#", fh)
    writeLines("exts_list = [", fh)
    forget.this = lapply(unlist(subset(packages, Repo == 'base')$Package), function(pkg) {writeLines(sprintf("    '%s',", pkg), fh)})
    writeLines("]",fh)
    writeLines("", fh)
}

#
# Compile RPlus EasyConfig and write to file.
#
writeECRPlus <- function (fh, version, deps, packages, repos, toolchain.name, toolchain.version, rplus.versionsuffix) {
    writeLines("#", fh)
    writeLines("# This EasyBuild config file for RPlus was generated with generateEasyConfig.R", fh)
    writeLines("#", fh)
    writeLines("easyblock = 'Bundle'", fh)
    writeLines("name = 'RPlus'", fh)
    writeLines(paste("version = '", version, "'", sep=''), fh)
    writeLines(paste("versionsuffix = '", rplus.versionsuffix, "'", sep=''), fh)
    writeLines("homepage = 'http://www.r-project.org/'", fh)
    writeLines('description = """R is a free software environment for statistical computing and graphics."""', fh)
    writeLines("moduleclass = 'lang'", fh)
    writeLines("modextrapaths = {'R_LIBS': ['library', '']}", fh)
    writeLines(paste("toolchain = {'name': '", toolchain.name, "', 'version': '", toolchain.version, "'}", sep=''), fh)
    writeLines("", fh)
    writeLines("#", fh)
    writeLines("# You may need to include a more recent Python to download R packages from HTTPS based URLs", fh)
    writeLines("# when the Python that comes with your OS is too old and you encounter:", fh)
    writeLines("#     SSL routines:SSL23_GET_SERVER_HELLO:sslv3 alert handshake failure", fh)
    writeLines("# In that case make sure to include a Python as builddependency. ", fh)
    writeLines("# This Python should not be too new either: it's dependencies like for example on ncursus should be compatible with R's dependencies.", fh)
    writeLines("# The alternative is to replace the https URLs with http URLs in the generated EasyConfig.", fh)
    writeLines("#", fh)
    writeLines("#builddependencies = [", fh)
    writeLines("#    ('Python', '3.7.4')", fh)
    writeLines("#]", fh)
    writeLines("", fh)
    writeLines("dependencies = [", fh)
    writeLines("    ('R', '%(version)s', '-bare'),", fh)
    writeLines(paste("    ('GMP', '",                 deps[['GMP']],                 "'),", sep=''), fh)
    writeLines(paste("    ('UDUNITS', '",             deps[['UDUNITS']],             "'),", sep=''), fh)
    writeLines(paste("    ('ImageMagick', '",         deps[['ImageMagick']],         "'),", sep=''), fh)
    writeLines(paste("    ('MariaDB-connector-c', '", deps[['MariaDB-connector-c']], "'),", sep=''), fh)
    writeLines(paste("    ('NLopt', '",               deps[['NLopt']],               "'),", sep=''), fh)
    writeLines("]", fh)
    writeLines("", fh)
    writeLines("#", fh)
    writeLines("# The '.' is a silly workaround to check for whatever current dir as workaround", fh)
    writeLines("# until an updated RPackage is available, which installs extension R packages in a library subdir.", fh)
    writeLines("#", fh)
    writeLines("sanity_check_paths = {", fh)
    writeLines("    'files': [],", fh)
    writeLines("    'dirs': [('library', '.')],", fh)
    writeLines("}", fh)
    writeLines("", fh)
    writeLines("package_name_tmpl = '%(name)s_%(version)s.tar.gz'", fh)
    writeLines("exts_defaultclass = 'RPackage'", fh)
    writeLines("exts_filter = ('R -q --no-save', 'library(%(ext_name)s)')", fh)
    writeLines("", fh)
    for (this.repo in names(repos)) {
        writeLines(paste(this.repo, '_options = {', sep=''), fh)
        writeLines("    'source_urls': [", fh)
        forget.this = lapply(unlist(repos[this.repo]), 
                function(url) {
                    #
                    # Switch any https URLs to insecure http.
                    # If you do want to use https make sure you have a recent Python in your build environment.
                    # See also note on builddependencies above...
                    #
                    url = sub('https:', 'http:', url)
                    writeLines(sprintf("        '%s',", url), fh)
                }
        )
        writeLines("    ],", fh)
        writeLines("    'source_tmpl': package_name_tmpl,", fh)
        writeLines("}", fh)
    }
    writeLines("", fh)
    writeLines("#", fh)
    writeLines("# R package list.", fh)
    writeLines("#   * Order of packages is important!", fh)
    writeLines("#   * Packages should be specified with fixed versions!", fh)
    writeLines("#", fh)
    writeLines("exts_list = [", fh)
    forget.this = apply(subset(packages, Repo != 'base', select=c('Package', 'Version', 'Repo')), 1,
            function(this.pkg) {
                this.pkg <- as.list(this.pkg);
                writeLines(sprintf("    ('%s', '%s', %s_options),", this.pkg$Package, this.pkg$Version, this.pkg$Repo), fh)
            }
    )
    writeLines("]",fh)
}

#
##
### Main.
##
#

#
# Read script arguments
#
cargs <- commandArgs(TRUE)
args=NULL
if(length(cargs)>0) {
    flags = grep("^--.*",cargs)
    values = (1:length(cargs))[-flags]
    args[values-1] = cargs[values]
    if(length(args)<tail(flags,1)) {
        args[tail(flags,1)] = NA
    }
    names(args)[flags]=cargs[flags]
}
arglist = c('--od', '--tc', '--vs', '--ll', NA)

#
# Handle arguments required to setup logging first.
#
if (is.element('--ll', names(args))) {
    log_level = args['--ll']
    log_level.position <- which(names(logging::loglevels) == log_level)
    if(length(log_level.position) < 1) {
        logging::levellog(loglevels[['WARN']], paste('Illegal log level ', log_level, ' specified.', sep=''))
        # Use default log level.
        log_level = 'INFO'
    }
    # Use the given log level.
} else {
    # Use default log level.
    log_level = 'INFO'
}

#
# Change the log level of both the root logger and it's default handler (STDOUT).
#
logging::setLevel(log_level)
logging::setLevel(log_level, logging::getHandler('basic.stdout'))
logging::levellog(loglevels[['INFO']], paste('Log level set to ', log_level, '.', sep=''))

#
# Check other arguments.
#
wrong.flags = length(args) == 0
if (!wrong.flags) wrong.flags = !all(names(args) %in% arglist)
if (!wrong.flags) wrong.flags = is.na(args['--tc'])

if(wrong.flags) {
    if (!all(names(args) %in% arglist)) {
        logging::levellog(loglevels[['FATAL']], paste('Illegal parameter name or bad syntax for ', names(args)[!(names(args) %in% arglist)], '!', sep=''))
    }
    usage()
}

#
# Process other arguments.
#
output.dir          = args['--od']
toolchain           = args['--tc']
rplus.versionsuffix = args['--vs'] # For RPlus.

if (is.na(args['--od'])) {
    output.dir = getwd() # default
}
if (is.na(args['--tc'])) {
    logging::levellog(loglevels[['FATAL']], 'Tool chain must be specified with --tc name/version.')
    usage()
} else { 
    toolchain <- strsplit(toolchain, '/')
    toolchain.name    = toolchain[[1]][1]
    toolchain.version = toolchain[[1]][2]
    if (is.na(toolchain.version) || is.na(toolchain.version)) {
        logging::levellog(loglevels[['FATAL']], 'Tool chain must be specified with --tc name/version.')
        usage()
    }
}
if (is.na(args['--vs'])) {
    logging::levellog(loglevels[['FATAL']], 'Version suffix must be specified with --vs YY.MM.incremental_release_number.')
    usage()
} else {
    if (grepl('[1-9][0-9].[0-1][0-9].[1-9][0-9]*', rplus.versionsuffix)) {
        rplus.versionsuffix = paste('-v', rplus.versionsuffix, sep='')
        logging::levellog(loglevels[['DEBUG']], paste('Will use RPlus version suffix: ', rplus.versionsuffix, '.', sep=''))
    } else {
        logging::levellog(loglevels[['FATAL']], 'Version suffix must be specified with --vs YY.MM.incremental_release_number.')
        usage()
    }
}

#
# Get R version.
#
R.version <- version
R.version.full = paste(get('major', R.version), get('minor', R.version), sep='.')

#
# Update versions of dependencies using "module list dependency" from commandline.
#
dependencies = setNames(lapply(names(dependency_defaults), getDepModuleVersion, toolchain.name=toolchain.name), names(dependency_defaults))

#
# Create file handles.
#
logging::levellog(loglevels[['DEBUG']], 'Compiling paths and filehandles for output files...')
output.path.r     = paste(output.dir, '/R-',     R.version.full, '-', toolchain.name, '-', toolchain.version, '-bare',             '.eb', sep='')
output.path.rplus = paste(output.dir, '/RPlus-', R.version.full, '-', toolchain.name, '-', toolchain.version, rplus.versionsuffix, '.eb', sep='')
logging::levellog(loglevels[['INFO']], paste('Will store R     EasyConfig in', output.path.r))
logging::levellog(loglevels[['INFO']], paste('Will store RPlus EasyConfig in', output.path.rplus))
fh.r = file(output.path.r, 'w')
fh.rplus = file(output.path.rplus, 'w')

#
# Get list all installed packages (in alphabetic order).
#
installedPackages <- rownames(installed.packages(lib.loc = NULL, priority = NULL, noCache = TRUE))

#
# Supplement list of BioConductor repository URLs, which already contains the 'release' URLs, 
# with the repo URLs for the specific BioConductor version that is compatible with this version of R.
#
if (compareVersion(paste(get('major', R.version), get('minor', R.version), sep='.'), '3.5')) {
    if (!requireNamespace("BiocManager", quietly = TRUE)) {install.packages("BiocManager")}
    library('BiocManager')
    biocRepos <- repositories()
} else {
    source("http://bioconductor.org/biocLite.R")
    biocRepos <- biocinstallRepos()
}
biocVersionedRepos <- subset(biocRepos, grepl('bioconductor', biocRepos))
biocVersionedRepoURLs <- paste(biocVersionedRepos, '/src/contrib/', sep='')
repos$bioconductor$active <- append(repos$bioconductor$active, biocVersionedRepoURLs)

#
# Supplement list of all installed versioned packages with
#  * their version numbers
#  * their repos
# and re-order based on dependencies where applicable.
#
installedPackages   = getPackageTree(installedPackages, repos)

#
# Calculate R package stats.
#
repolessPackages    = subset(installedPackages, is.na(installedPackages$Repo))
packagesTotal       = nrow(installedPackages)
packagesUnavailable = nrow(repolessPackages)
packagesResolved    = packagesTotal - packagesUnavailable
if (packagesUnavailable > 0) {
    lapply(as.list(repolessPackages)$Package, function(repolessPackage) {
            logging::levellog(loglevels[['WARN']], paste('Failed to determine repo origin for package', repolessPackage, '.'))
        }
    )
    if (packagesUnavailable > 1) {
        logging::levellog(loglevels[['WARN']], paste('Failed to determine repo origin for', packagesUnavailable, 'packages!'))
    } else { 
        logging::levellog(loglevels[['WARN']], paste('Failed to determine repo origin for', packagesUnavailable, 'package!'))
    }
}

#
# Report R package stats.
#
nsmall = 2
numberwidth = floor(log(packagesTotal,10))+1
logging::levellog(loglevels[['INFO']], paste('=======================================================================', paste(rep('=', numberwidth), collapse=''), sep=''))
logging::levellog(loglevels[['INFO']], paste(': Total R packages processed:                                ', format(packagesTotal, width = numberwidth), sep=''))
this.percentage = round(packagesResolved / packagesTotal * 100, 2)
logging::levellog(loglevels[['INFO']], paste(':  * Resolved packages    (will be added to EasyConfig):     ', format(packagesResolved, width = numberwidth), '  (', format(this.percentage, width = 6, nsmall = nsmall), '%)', sep=''))
this.percentage = round(packagesUnavailable / packagesTotal * 100, 2)
logging::levellog(loglevels[['INFO']], paste(':  * Unavailable packages (missing from EasyConfig):         ', format(packagesUnavailable, width = numberwidth), '  (', format(this.percentage, width = 6, nsmall = nsmall), '%)', sep=''))
logging::levellog(loglevels[['INFO']], paste('=======================================================================', paste(rep('=', numberwidth), collapse=''), sep=''))

#
# Create EasyBuild EasyConfig
#
writeECR(fh.r,         R.version.full, dependencies, installedPackages, repos, toolchain.name, toolchain.version)
writeECRPlus(fh.rplus, R.version.full, dependencies, installedPackages, repos, toolchain.name, toolchain.version, rplus.versionsuffix)

#
# Close file handle.
#
close(fh.r)
close(fh.rplus)

#
# We are done!
#
logging::levellog(loglevels[['INFO']], 'Finished!')
logging::levellog(loglevels[['INFO']], paste('=======================================================================', paste(rep('=', numberwidth), collapse=''), sep=''))

#
# Inform user how to insert checksums.
#
logging::levellog(loglevels[['INFO']], 'Run the EasyBuild "eb" command like this to insert checksums for the sources into the generated EasyConfigs:')
logging::levellog(loglevels[['INFO']], ':    module load EasyBuild')
logging::levellog(loglevels[['INFO']], paste(':    eb --inject-checksums=sha256 --stop=ready ', output.path.r, sep=''))
logging::levellog(loglevels[['INFO']], paste(':    eb --inject-checksums=sha256 --stop=ready ', output.path.rplus, sep=''))
logging::levellog(loglevels[['INFO']], paste('=======================================================================', paste(rep('=', numberwidth), collapse=''), sep=''))
