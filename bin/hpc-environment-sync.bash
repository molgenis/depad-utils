#!/bin/bash
#
# Script for syncing software and reference data sets
#   from primary install/deploy location (${SOURCE_ROOT_PATH})    (/apps/...     in file system layout below)
#   to tmp file systems (${DESTINATION_MOUNT_POINT_PARENTS[@]})   (/.envsync/... in file system layout below)
# in the UMCG cluster environment.
#
#
##
### Global shared HPC environment file system layout:
##
#
#  /apps/software/${package}/${version}/           Software deployed with EasyBuild.
#
#       /modules/all/${package}/${version}/        Module files for use with Lmod to modify environment to load/unload software deployed with EasyBuild.
#
#       /sources/[a-z]/${package}/                 Source code downloaded by EasyBuild.
#
#       /data/${provider}/${data_set}/$version/    Reference data sets available to all (Hence not group specific data).
#                                                  E.g. the human reference genome.
#                                                  Data is unmodified "as is".
#
#       /data/${provider}/${data_set}/${version}/${package}/${version}/    Reference data indexed / reformatted for use with specific version of software.
#
#       /cache/                                    Data that must be sync-ed to local storage on compute nodes optimized for random IO.
#                                                  This can be anything - software, reference data, etc.
#                                                  Please use same naming / structure as described above where possible.
#
#  /.envsync/tmp*/apps/      Rsynced copies of /apps/ on various HP tmp file systems.
#
#  /groups/${group}/arc*/    Group specific folder for archived data:  slow, cheap,     shared, with backups.
#                  /prm*/    Group specific folder for permanent data: slow, expensive, shared, with backups.
#                  /tmp*/    Group specific folder for temporary data: fast, expensive, shared, without backups.
#                  /scr*/    Group specific folder for scratch data:   fast, expensive, local,  without backups.
#
#  /home/${user}/    Individual home dirs.
#

#
##
### Functions.
##
#
function showHelp() {
	#
	# Display commandline help on STDOUT.
	#
	cat <<EOH

Usage:

	$(basename "${0}") [-l] -a
	$(basename "${0}") [-l] -r relative/path/to/ReferenceData/
	$(basename "${0}") [-l] -c relative/path/to/CacheData/
	$(basename "${0}") [-l] -m ModuleName/ModuleVersion

Details:

	-l	List: Do not perform actual sync, but only list changes instead (dry-run).

	-a	All: syncs complete HPC environment (software, modules & reference data) from ${SOURCE_ROOT_PATH}.

	-r	Reference data: syncs only the specified data.
		Path may be either an absolute path or relative to ${SOURCE_ROOT_PATH}${REFDATA_DIR_NAME}/.

	-c	Cache data: syncs only the specified data.
		Path may be either an absolute path or relative to ${SOURCE_ROOT_PATH}${CACHE_DIR_NAME}/.

	-m	Module: syncs only the specified module.
		The tool must have been deployed with EasyBuild, with accompanying "module" file 
		and specified using NAME/VERSION as per "module" command syntax.
		Will search for modules in ${SOURCE_ROOT_PATH}${MODULES_DIR_NAME}/
		for software installed in  ${SOURCE_ROOT_PATH}${SOFTWARE_DIR_NAME}/
		The special NAME/VERSION combination ANY/ANY will sync all modules.

To change the options like source and destination dirs modify the ${SCRIPT_CONFIG_FILE} config file.

Currently configured destination mount points to search for Logical File Systems (LFS) to sync environment to: 
	${DESTINATION_MOUNT_POINT_PARENTS[@]}

Destinations to sync the cache to are determined dynamically by querying the Slurm config from ${SLURM_HOST}
for a list of compute nodes with a local Slurm "TmpFS" disk.

EOH
	#
	# Clean up.
	#
	rm -Rf "${TMP_DIR}"
	#
	# Reset trap and exit.
	#
	trap - EXIT
	exit 0
}

function reportError() {
	local PROBLEMATIC_LINE="${1}"
	local exit_status="${2:-${?}}"
	local ERROR_MESSAGE
	local ROLE_USER
	local REAL_USER
	local errorMessage
	ERROR_MESSAGE=$(cat "${TMP_LOG}" 2> /dev/null) || true
	ERROR_MESSAGE="${ERROR_MESSAGE:-Unknown error.}"
	errorMessage="${3:-"${ERROR_MESSAGE}"}"
	ROLE_USER="$(whoami)"
	REAL_USER="$(logname)"
	local DETAILED_LOGS
	DETAILED_LOGS="$(cat "${RSYNC_LOG}" 2> /dev/null)" || true
	#
	# Notify syslog.
	#
	logger -s "${HOSTNAME} - ${SCRIPT_NAME}:${PROBLEMATIC_LINE}: FATAL: Sync executed by ${ROLE_USER}(${REAL_USER}) FAILED!"
	logger -s "${HOSTNAME} - ${SCRIPT_NAME}:${PROBLEMATIC_LINE}: Exit code = ${exit_status}"
	logger -s "${HOSTNAME} - ${SCRIPT_NAME}:${PROBLEMATIC_LINE}: Error message = ${errorMessage}"
	logger -s "${HOSTNAME} - ${SCRIPT_NAME}:${PROBLEMATIC_LINE}: Details = ${DETAILED_LOGS:-none.}"
	#
	# Notify admins by e-mail only if this is an automated (cron) sync job (running in "DUMB" pseudo terminal).
	#
	if [[ "${TERM}" == 'dumb' ]]; then
		echo "
Dear ${SYS_GROUP} group,

It is I, the ${SCRIPT_NAME} script executing on ${HOSTNAME} by ${ROLE_USER} (${REAL_USER}).
I gave up at line ${PROBLEMATIC_LINE} and your sync FAILED miserably!
The exit code of the last command was ${exit_status} with error message ${errorMessage}.
Further details follow below if available...
Please fix either me, ${HOSTNAME} or ${ROLE_USER} (${REAL_USER}), whichever is broken...

Morituri te salutant!

===============================================================================
${DETAILED_LOGS:-}
" \
		| mail -s "${SCRIPT_NAME} on ${HOSTNAME} FAILED!" \
			-r "${EMAIL_FROM}" \
			"${EMAIL_TO}" \
		|| logger -s "${HOSTNAME} - ${SCRIPT_NAME}:${LINENO}: FATAL: Could not send email."
	fi
	#
	# Clean up.
	#
	rm -Rf "${TMP_DIR}"
	#
	# Reset trap and exit.
	#
	trap - EXIT
	exit "${exit_status}"
}

#
# Perform the rsync for all sources that need to be synced to all destinations.
#
function performSync() {
	local continue_on_error="${1:-}"
	cd "${SOURCE_ROOT_PATH}"
	for (( i = 0 ; i < "${#RSYNC_SOURCES[@]}" ; i++ ))
	do
		for (( j = 0 ; j < "${#AVAILABLE_DESTINATION_ROOT_DIRS[@]}" ; j++ ))
		do
			RSYNC_SOURCE="${RSYNC_SOURCES[${i}]}"
			RSYNC_DESTINATION="${AVAILABLE_DESTINATION_ROOT_DIRS[${j}]}"
			echo -n "INFO: Rsyncing ${RSYNC_SOURCE} to ${RSYNC_DESTINATION}... "
			if [[ "${LIST}" -eq 1 ]]; then
				{
					echo '================================================================================================================'
					echo "	Dry run stats for syncing ${RSYNC_SOURCE} to ${RSYNC_DESTINATION}:"
					echo '================================================================================================================'
				} >> "${RSYNC_LOG}"
			fi
			set +e
			rsync "${RSYNC_OPTIONS[@]}" \
				"${RSYNC_SOURCE}" \
				"${RSYNC_DESTINATION}" \
				>> "${RSYNC_LOG}" 2>&1
			XVAL="${?}"
			set -e
			if [[ "${XVAL}" -eq 0 || "${XVAL}" -eq 24 ]]; then
				echo 'done.'
			else
				echo ''
				if [[ "${continue_on_error:-}" == 'continue_on_error' ]]; then
					echo "ERROR: Rsync of source (${RSYNC_SOURCE}) to destination (${RSYNC_DESTINATION}) started on ${START_TS} failed."
				else
					reportError "${LINENO}" "${XVAL}" "Rsync of source (${RSYNC_SOURCE}) to destination (${RSYNC_DESTINATION}) started on ${START_TS} failed."
				fi
			fi
		done
	done
}

function createConfigTemplate () {
	(cat > "${SCRIPT_CONFIG_FILE}.template"  <<EOCT 

##########################################################
# Configuration file for the ${SCRIPT_NAME} script.
#
#   * Listing variables in bash syntax
#   * To activate this config:
#     * Edit this file and 
#     * Remove the .template suffix from the filename  
#
##########################################################

#
# System account, group used for the rsync.
#  * Group on SOURCE will be recursively changed to this one before sync.
#
#SYS_USER='umcg-envsync'
#SYS_GROUP='umcg-depad'
#
# Perms for environment on SOURCE
#  * These permissions will be applied recursively on SOURCE before sync.
#  * These are NOT the permissions applied to the DESTINATION (those are controlled by rsync options.)
#
#SYS_FILE_PERMS_EXECUTABLE='0775'
#SYS_FILE_PERMS_REGULAR='0664'
#SYS_FILE_PERMS_CHMOD='ug+rwX,o+rX,o-w'
#SYS_FOLDER_PERMS='2775'

#
# Original location where we deployed our software, their modules and reference data.
#
#SOURCE_ROOT_PATH='/apps/'
#SOFTWARE_DIR_NAME='software'
#MODULES_DIR_NAME='modules'
#REFDATA_DIR_NAME='data'
#CACHE_DIR_NAME='cache'

#
# Locations on tmp* file system where we want a copy of our deployed tools + resources.
#
#declare -a DESTINATION_MOUNT_POINT_PARENTS=('/.envsync/')

#
# Name of the host where we will try to execute the Slurm sinfo and scontrol commands
# in order to find the list of compute nodes, which have cache on a local file system,
# where we can store a copy of our cache.
#
#declare SLURM_HOST=user_interface_hostname

#
# Should the script delete old stuff in DESTINATION when it is no longer present in SOURCE?
#
DELETE_OLD=0

#
# Email reporting of failures.
#
#EMAIL_FROM=''
#EMAIL_TO=''

EOCT
)	|| {
		echo "FATAL: Cannot find/access ${SCRIPT_CONFIG_FILE} and could not create a template config file with disabled options either."
		trap - EXIT
		exit 1
	}
}

#
##
### Bash sanity and error trapping.
##
#

#
# Bash sanity.
#
set -u
set -e
set -o pipefail

#
# Trap all exit signals: HUP(1), INT(2), QUIT(3), TERM(15), ERR
#
trap 'reportError $LINENO' HUP INT QUIT TERM EXIT ERR

#
##
### Configure sync job.
##
#

#
# Get the name of the machine where the script was executed.
#
SCRIPT_NAME=$(basename "$0" .bash)
if [[ -z "${HOSTNAME:-}" ]]; then
	HOSTNAME="$(hostname)"
fi
SCRIPT_CONFIG_DIR="${HOME}/.config/${SCRIPT_NAME}/"

#
# Check if config exists.
#
# shellcheck disable=SC2174
mkdir -p -m 700 "${SCRIPT_CONFIG_DIR}"
SCRIPT_CONFIG_FILE="${SCRIPT_CONFIG_DIR}/${SCRIPT_NAME}.cfg"
if [[ -r "${SCRIPT_CONFIG_FILE}" && -f "${SCRIPT_CONFIG_FILE}" ]]; then
	# Disable shellcheck code syntax checking for config files.
	# shellcheck source=/dev/null
	source "${SCRIPT_CONFIG_FILE}" || reportError "${LINENO}" "${?}" "Cannot source ${SCRIPT_CONFIG_FILE}."
else
	createConfigTemplate
	logger -s "${HOSTNAME} - ${SCRIPT_NAME}:${LINENO}: FATAL: Cannot find/access ${SCRIPT_CONFIG_FILE}!"
	logger -s "${HOSTNAME} - ${SCRIPT_NAME}:${LINENO}: INFO: Created a template config file with disabled options: ${SCRIPT_CONFIG_FILE}.template."
	logger -s "${HOSTNAME} - ${SCRIPT_NAME}:${LINENO}: INFO: Edit + rename template and try again."
	trap - EXIT
	exit 1
fi

START_TS=$(date "+%Y-%m-%d-T%H%M")
TMP_DIR="${TMPDIR:-/tmp}/${SCRIPT_NAME}/"
#echo "DEBUG: Using TMP_DIR: ${TMP_DIR}."
RSYNC_LOG="${TMP_DIR}/${SCRIPT_NAME}-${START_TS}.log"
TMP_LOG="${TMP_DIR}/tmp-${START_TS}.log"

#
# Create tmp dir.
#
mkdir -p "${TMP_DIR}/" || reportError "${LINENO}" "${?}" "Cannot create ${TMP_DIR}."
test -d "${TMP_DIR}"   || reportError "${LINENO}" "${?}" "Cannot access ${TMP_DIR}."
touch "${TMP_LOG}"     || reportError "${LINENO}" "${?}" "Cannot create ${TMP_LOG}."

#
# Initialise empty rsync log file, so emailing the logs won't fail, because the log does not yet exist.
#
touch "${RSYNC_LOG}" 2> "${TMP_LOG}"

#
##
### Process commandline arguments.
##
#

#
# Get commandline arguments.
#
ALL=0
CACHE=0
MODULE=0
REFDATA=0
LIST=0
SOURCE=''
while getopts ":halc:r:m:" opt; do
	case "${opt}" in
		h)
			showHelp
			;;
		a)
			ALL=1
			;;
		l)
			LIST=1
			;;
		c)
			CACHE=1
			SOURCE="${OPTARG}"
			;;
		m)
			MODULE=1
			SOURCE="${OPTARG}"
			;;
		r)
			REFDATA=1
			SOURCE="${OPTARG}"
			;;
		\?)
			reportError "${LINENO}" '1' "Invalid option -${OPTARG}. For help try: $(basename "${0}") -h"
			;;
		:)
			reportError "${LINENO}" '1' "Option -${OPTARG} requires an argument. For help try: $(basename "${0}") -h"
			;;
		*)
			reportError "${LINENO}" '1' "Unhandled option. For help try: $(basename "${0}") -h"
			;;
	esac
done

#
# Check commandline arguments.
#
ARG_SUM=$((${ALL}+${REFDATA}+${MODULE}+${CACHE}))

if [[ "${ARG_SUM}" -eq 0 ]]; then
	#
	# No commandline arguments specified.
	#
	showHelp
elif [[ "${ARG_SUM}" -gt 1 ]]; then
	reportError "${LINENO}" '1' "Too many mutually exclusive arguments specified. For help try: $(basename "${0}") -h"
fi

#
##
### Check environment.
##
#

#
# Check if we are running with the correct account + permissions.
#
CURRENT_USER=$(whoami)
if [[ "${CURRENT_USER}" != "${SYS_USER}" ]]; then
	reportError "${LINENO}" '1' "This script must be executed by user ${SYS_USER}, but you are ${CURRENT_USER}."
fi
CURRENT_GROUP=$(id -gn)
if [[ "${CURRENT_GROUP}" != "${SYS_GROUP}" ]]; then
	reportError "${LINENO}" '1' "This script must be executed by user ${SYS_USER} with primary group ${SYS_GROUP}, but your current primary group is ${CURRENT_GROUP}."
fi

#
# Define rsync options.
#
# Fairly standard RSYNC_OPTIONS='-avRK'
#   where -a = archive mode = -rlptgoD.
# We don't sync ownership of the files.
# Instead all secondary copies on the destinations are owned by ${SYS_USER}.
#
declare -a RSYNC_OPTIONS=('-rlptgDvRK')
#
# We don't sync permissions and change them explicitly.
#
RSYNC_OPTIONS+=('--perms' '--chmod=u=rwX,go=rX')
if [[ "${DELETE_OLD}" -eq 1 ]]; then
	echo "WARN: Cleanup of outdated ${SOURCE_ROOT_PATH} data is enabled for ${DESTINATION_MOUNT_POINT_PARENTS[*]}."
	RSYNC_OPTIONS+=('--delete-after')
fi
if [[ "${LIST}" -eq 1 ]]; then
	echo 'WARN: List mode enabled: will only list what is out of sync and needs to be updated, but will not perform actual sync.'
	RSYNC_OPTIONS+=('-nu')
else
	RSYNC_OPTIONS+=('-q')
fi

echo "INFO: RSYNC_OPTIONS contains ${RSYNC_OPTIONS[*]}"

#
##
### Synchronise HPC environments to shared file systems.
##
#

declare -a AVAILABLE_DESTINATION_ROOT_DIRS=()
declare -a RSYNC_SOURCES=()
#
# Check if all destinations are available and remove destinations, which are offline!
#
# This is critically essential as syncing to a mount point with missing mount would add the data to the disk containing the mount point, 
# which is usually a relatively small disk containing the OS. Running out of space on the local system disk, will crash a server!
#
if [[ "${ALL}" -eq 1 ]] || [[ "${REFDATA}" -eq 1 ]] || [[ "${MODULE}" -eq 1 ]]; then
	for (( i = 0 ; i < "${#DESTINATION_MOUNT_POINT_PARENTS[@]}" ; i++ ))
	do 
		#
		# Check for presence of folders for logical file system (LFS) names
		# and if present whether they contain a copy of ${SOURCE_ROOT_PATH}.
		#
		found="$(find "${DESTINATION_MOUNT_POINT_PARENTS[${i}]}" -mindepth 1 -maxdepth 1 -type d)"
		readarray -t LFS_MOUNT_POINTS <<< "${found}"
		for (( j = 0 ; j < "${#LFS_MOUNT_POINTS[@]}" ; j++ ))
		do
			DESTINATION_ROOT_DIR="${LFS_MOUNT_POINTS[${j}]}${SOURCE_ROOT_PATH}"
			if [[ -e "${DESTINATION_ROOT_DIR}" ]] && [[ -r "${DESTINATION_ROOT_DIR}" ]] && [[ -w "${DESTINATION_ROOT_DIR}" ]]; then
				if [[ "${#AVAILABLE_DESTINATION_ROOT_DIRS[@]}" -eq 0 ]]; then
					AVAILABLE_DESTINATION_ROOT_DIRS=("${DESTINATION_ROOT_DIR}")
				else
					AVAILABLE_DESTINATION_ROOT_DIRS=("${AVAILABLE_DESTINATION_ROOT_DIRS[@]:-}" "${DESTINATION_ROOT_DIR}")
				fi
			else
				echo "WARN: ${DESTINATION_ROOT_DIR} not available (symlink dead or mount missing). Skipping rsync to ${DESTINATION_ROOT_DIR}."
			fi
		done
	done
fi

if [[ "${#AVAILABLE_DESTINATION_ROOT_DIRS[@]}" -gt 0 ]]; then
	echo "INFO: AVAILABLE_DESTINATION_ROOT_DIRS contains ${AVAILABLE_DESTINATION_ROOT_DIRS[*]}"
	if [[ "${ALL}" -eq 1 ]]; then
		#
		# Add all applications, their modules and reference data to the list of data to rsync.
		# Note: basically this includes everything except for the cache and sources, which we don't need on cluster nodes.
		#
		RSYNC_SOURCES+=("${SOFTWARE_DIR_NAME}")
		RSYNC_SOURCES+=("${MODULES_DIR_NAME}")
		RSYNC_SOURCES+=("${REFDATA_DIR_NAME}")
	elif [[ "${REFDATA}" -eq 1 ]]; then
		#
		# Remove leading ${SOURCE_ROOT_PATH}/${REFDATA_DIR_NAME}/ from SOURCE if an absolute path was specified.
		#
		shopt -s extglob
		SOURCE="${SOURCE##"${SOURCE_ROOT_PATH}"*"${REFDATA_DIR_NAME}"*([/])}"
		#
		# Find and add only specified reference data to list of data to rsync.
		#
		cd "${SOURCE_ROOT_PATH}/" 2> "${TMP_LOG}" || reportError "${LINENO}" "${?}"
		if [[ -e "${SOURCE_ROOT_PATH}/${REFDATA_DIR_NAME}/${SOURCE}" ]]; then
			echo "INFO: Found reference data ${SOURCE}."
		else
			reportError "${LINENO}" "${?}" "Cannot find reference data ${SOURCE} in ${SOURCE_ROOT_PATH}/${REFDATA_DIR_NAME}/."
		fi
		# Create list of RSYNC SOURCES
		RSYNC_SOURCES+=("${REFDATA_DIR_NAME}/${SOURCE}")
	elif [[ "${MODULE}" -eq 1 ]]; then
		#
		# Find and add only specified module to list of data to rsync.
		#
		IFS='/' read -r -a MODULE_SPEC <<< "${SOURCE}" || reportError "${LINENO}" "${?}"
		if [[ "${#MODULE_SPEC[@]}" -ne 2 ]]; then
			reportError "${LINENO}" "${?}" "Illegal module specification ${SOURCE}. Module must be specified in format MODULE_NAME/MODULE_VERSION."
		fi
		MODULE_NAME="${MODULE_SPEC[0]}"
		#echo "BEDUG: MODULE_NAME    = ${MODULE_NAME}"
		MODULE_VERSION="${MODULE_SPEC[1]}"
		#echo "DEBUG: MODULE_VERSION = ${MODULE_VERSION}"
		if [[ "${MODULE_NAME}" == 'ANY' && "${MODULE_VERSION}" == 'ANY' ]]; then
			#
			# Add all applications and their modules to the list of data to rsync.
			#
			RSYNC_SOURCES+=("${SOFTWARE_DIR_NAME}")
			RSYNC_SOURCES+=("${MODULES_DIR_NAME}")
		else
			#
			# Find modules: Lmod modules may be present in multiple "category" sub dirs.
			#
			# Regular module files are present
			#  * once as a file in the "all" category sub dir
			#  * and in one or more other category sub dirs as symlink to the one in "all".
			#
			# Alternatively MODULE_NAME/MODULE_VERSION could be an alias.
			# E.g. Java/21-LTS -> Java/21.0.7
			# Such aliases are not stored in regular module files per MODULE_VERSION,
			# but in one .modulerc file per MODULE_NAME instead.
			#
			# Lmod module files and .modulerc files can be in
			#	* either TCL format for backward compatibility (file name without extension)
			#	* or Lua format (file name with *.lua extension).
			#
			found_modules="$(find "${SOURCE_ROOT_PATH}/${MODULES_DIR_NAME}/" -wholename '*/'"${MODULE_NAME}/${MODULE_VERSION}"'*' \
					| sed "s|${SOURCE_ROOT_PATH}//*${MODULES_DIR_NAME}//*||")" \
				|| reportError "${LINENO}" "${?}" "Failed to execute find + sed to search for module files in ${SOURCE_ROOT_PATH}/${MODULES_DIR_NAME}/."
			found_dotmodulercs="$(find "${SOURCE_ROOT_PATH}/${MODULES_DIR_NAME}/" -wholename '*/'"${MODULE_NAME}/.modulerc"'*' \
					| sed "s|${SOURCE_ROOT_PATH}//*${MODULES_DIR_NAME}//*||")" \
				|| reportError "${LINENO}" "${?}" "Failed to execute find + sed to search for .modulerc files in ${SOURCE_ROOT_PATH}/${MODULES_DIR_NAME}/."
			readarray -t VERSIONED_MODULES < <(printf '%s' "${found_modules}")
			readarray -t DOTMODULERCS < <(printf '%s' "${found_dotmodulercs}")
			if [[ "${#VERSIONED_MODULES[@]}" -ge 1 ]]; then
				echo "INFO: Found module file(s) for ${SOURCE}."
				#
				# Append to list of RSYNC SOURCES.
				#
				for VERSIONED_MODULE in "${VERSIONED_MODULES[@]}"; do
					RSYNC_SOURCES+=("${MODULES_DIR_NAME}/${VERSIONED_MODULE}")
					#echo "DEBUG: Appended ${MODULES_DIR_NAME}/${VERSIONED_MODULE} to RSYNC_SOURCES."
				done
			elif [[ "${#DOTMODULERCS[@]}" -ge 1 ]]; then
				found_module_in_dotmodulerc='false'
				for DOTMODULERC in "${DOTMODULERCS[@]}"; do
					if grep -q "${MODULE_VERSION}" "${SOURCE_ROOT_PATH}/${MODULES_DIR_NAME}/${DOTMODULERC}"; then
						found_module_in_dotmodulerc='true'
						#
						# Append to list of RSYNC SOURCES.
						#
						RSYNC_SOURCES+=("${MODULES_DIR_NAME}/${DOTMODULERC}")
						#echo "DEBUG: Appended ${MODULES_DIR_NAME}/${DOTMODULERC} to RSYNC_SOURCES."
					fi
				done
				if [[ "${found_module_in_dotmodulerc}" == 'true' ]]; then
					echo "INFO: Found .modulerc file(s) for ${SOURCE}."
				else
					reportError "${LINENO}" '1' "Cannot find module version ${MODULE_VERSION} in a regular module file nor in any .modulerc file for ${MODULE_NAME} in ${SOURCE_ROOT_PATH}/${MODULES_DIR_NAME}/."
				fi
			else
				reportError "${LINENO}" '1' "Cannot find module file nor .modulerc file for ${MODULE_NAME}/${MODULE_VERSION} in ${SOURCE_ROOT_PATH}/${MODULES_DIR_NAME}/."
			fi
			#
			# Find dir where software is installed for this module.
			#
			if [[ -d "${SOURCE_ROOT_PATH}/${SOFTWARE_DIR_NAME}/${MODULE_NAME}/${MODULE_VERSION}" ]]; then
				#
				# Append to list of RSYNC SOURCES.
				#
				RSYNC_SOURCES+=("${SOFTWARE_DIR_NAME}/${MODULE_NAME}/${MODULE_VERSION}")
				#echo "DEBUG: Appended ${SOFTWARE_DIR_NAME}/${MODULE_NAME}/${MODULE_VERSION} to RSYNC_SOURCES."
			else
				reportError "${LINENO}" '1' "Cannot find software dir ${MODULE_NAME}/${MODULE_VERSION} in ${SOURCE_ROOT_PATH}/${SOFTWARE_DIR_NAME}/."
			fi
		fi
		#
		# Add the (updated) Lmod cache + timestamp as well.
		#
		RSYNC_SOURCES+=("${LMOD_CACHE_DIR/#${SOURCE_ROOT_PATH}/}")
		RSYNC_SOURCES+=("${LMOD_TIMESTAMP_FILE/#${SOURCE_ROOT_PATH}/}")
		#echo "DEBUG: Appended ${LMOD_CACHE_DIR/#${SOURCE_ROOT_PATH}/} to RSYNC_SOURCES."
		#echo "DEBUG: Appended ${LMOD_TIMESTAMP_FILE/#${SOURCE_ROOT_PATH}/} to RSYNC_SOURCES."
	fi
	echo "INFO: RSYNC_SOURCES contains ${RSYNC_SOURCES[*]}"
	#
	# Update Lmod cache when one or more module will be synchronized.
	#
	if [[ "${ALL}" -eq 1 ]] || [[ "${MODULE}" -eq 1 ]]; then
		UPDATE_LMOD_CACHE=$(command -v update_lmod_system_cache_files 2> /dev/null || echo -n 'missing')
		if [[ "${LMOD_VERSION%%.*}" -gt 6 ]]; then
			lmod_modulepath="${MODULEPATH}"
			#shellcheck disable=SC2016
			printf 'INFO: found lmod version > 6.x (%s); will use $MODULEPATH.\n' "${LMOD_VERSION}"
		else
			lmod_modulepath="${LMOD_DEFAULT_MODULEPATH}"
			#shellcheck disable=SC2016
			printf 'INFO: found lmod version <= 6.x (%s); will use $LMOD_DEFAULT_MODULEPATH.\n' "${LMOD_VERSION}"
		fi
		if [[ -x "${UPDATE_LMOD_CACHE}" ]]; then
			echo -n 'INFO: Updating Lmod cache... '
			"${UPDATE_LMOD_CACHE}" \
				-d "${LMOD_CACHE_DIR}" \
				-t "${LMOD_TIMESTAMP_FILE}" \
				"${lmod_modulepath}" \
				2> "${TMP_LOG}" || reportError "${LINENO}" "${?}"
			echo 'done!'
		else
			echo 'FAILED'
			reportError "${LINENO}" '1' 'update_lmod_system_cache_files missing or not executable; Cannot update Lmod cache: Giving up!'
		fi
	fi
	#
	# Recursively fix group + permissions on SOURCE (should not be necessary, but just in case :))
	#
	cd "${SOURCE_ROOT_PATH}"
	for (( i = 0 ; i < "${#RSYNC_SOURCES[@]}" ; i++ ))
	do
		echo "INFO: Trying to fix group and permissions on ${SOURCE_ROOT_PATH}${RSYNC_SOURCES[${i}]} recursively before sync."
		echo '      Should not be necessary, but just in case...'
		echo "      This may fail (depending on current group and permissions) if user '${SYS_USER}' does not own the files/folders."
		#
		# We use find to try to fix group + perms only when they are not correct.
		# This prevents permission denied errors when there is no need to change group or perms and we do not own the files/folders.
		#
		find "${RSYNC_SOURCES[${i}]}" \! -group "${SYS_GROUP}"                                                                         -exec chgrp "${SYS_GROUP}" '{}' \;            2> "${TMP_LOG}" || reportError "${LINENO}" "${?}"
		find "${RSYNC_SOURCES[${i}]}" \! -type d -a \! \( -perm "${SYS_FILE_PERMS_EXECUTABLE}" -o -perm "${SYS_FILE_PERMS_REGULAR}" \) -exec chmod "${SYS_FILE_PERMS_CHMOD}" '{}' \; 2> "${TMP_LOG}" || reportError "${LINENO}" "${?}"
		find "${RSYNC_SOURCES[${i}]}"    -type d -a \!    -perm "${SYS_FOLDER_PERMS}"                                                  -exec chmod "${SYS_FOLDER_PERMS}" '{}' \;     2> "${TMP_LOG}" || reportError "${LINENO}" "${?}"
	done
	#
	# Perform the rsync for all sources that need to be synced to all destinations.
	#
	performSync
else
	if [[ "${ALL}" -eq 1 ]] || [[ "${REFDATA}" -eq 1 ]] || [[ "${MODULE}" -eq 1 ]]; then
		echo "WARN: None of the destinations is available: skipping rsync!"
	fi
fi

#
##
### Synchronise cache to local file systems.
##
#
AVAILABLE_DESTINATION_ROOT_DIRS=()  # Reset list.
RSYNC_SOURCES=()  # Reset list.

if [[ "${ALL}" -eq 1 ]] || [[ "${CACHE}" -eq 1 ]]; then
	if [[ "${ALL}" -eq 1 ]]; then
		#
		# Add entire cache dir.
		#
		RSYNC_SOURCES=("${CACHE_DIR_NAME}")
	elif [[ "${CACHE}" -eq 1 ]]; then
		#
		# Remove leading ${SOURCE_ROOT_PATH}/${CACHE_DIR_NAME}/ from SOURCE if an absolute path was specified.
		#
		shopt -s extglob
		SOURCE="${SOURCE##"${SOURCE_ROOT_PATH}"*"${CACHE_DIR_NAME}"*([/])}"
		#
		# Find and add only specified cache data to list of data to rsync.
		#
		cd "${SOURCE_ROOT_PATH}/" 2> "${TMP_LOG}" || reportError "${LINENO}" "${?}"
		if [[ -e "${SOURCE_ROOT_PATH}/${CACHE_DIR_NAME}/${SOURCE}" ]]; then
			echo "INFO: Found cache data ${SOURCE}."
		else
			reportError "${LINENO}" "${?}" "Cannot find cache data ${SOURCE} in ${SOURCE_ROOT_PATH}/${CACHE_DIR_NAME}/."
		fi
		# Create list of RSYNC SOURCES
		RSYNC_SOURCES=("${CACHE_DIR_NAME}/${SOURCE}")
	fi
	echo "INFO: RSYNC_SOURCES contains ${RSYNC_SOURCES[*]}"
	declare -a DESTINATION_CACHE_DIRS=()
	if [[ -n "${SLURM_HOST:-}" ]]; then
		slurm_tmpfs_dir="$(ssh "${SLURM_HOST}" "scontrol show config | grep -i tmpfs | sed 's|.*= *||'")" \
			|| reportError "${LINENO}" "${?}" "Failed to get Slurm TmpFs path from Slurm 'scontrol show config' command on ${SLURM_HOST}."
		sinfo_result="$(ssh "${SLURM_HOST}" "sinfo --format='%N|%d' --Node --noheader")" \
			|| reportError "${LINENO}" "${?}" "Failed to get list of compute nodes from Slurm 'sinfo' command on ${SLURM_HOST}."
		while IFS='|' read -d $'\n' -r compute_node local_scratch_disk_size; do
			if [[ "${local_scratch_disk_size}" -gt 0 ]]; then
				DESTINATION_CACHE_DIRS+=("${compute_node}:${slurm_tmpfs_dir}/")
			fi
		done <<< "${sinfo_result}"
	else
		reportError "${LINENO}" '1' "The SLURM_HOST variable is not defined in ${SCRIPT_CONFIG_FILE}."
	fi
	if [[ "${#DESTINATION_CACHE_DIRS[@]}" -gt 0 ]]; then
		AVAILABLE_DESTINATION_ROOT_DIRS=("${DESTINATION_CACHE_DIRS[@]}")
		echo "INFO: AVAILABLE_DESTINATION_ROOT_DIRS contains ${AVAILABLE_DESTINATION_ROOT_DIRS[*]}"
		#
		# Perform the rsync for all sources that need to be synced to all destinations.
		#
		performSync continue_on_error
	else
		echo "WARN: No destination cache dirs available: skipping rsync!"
	fi
fi

#
##
### Sanity check.
##
#

#
# Parse log: rsync log should exist and should be empty.
#
if [[ "${LIST}" -eq 1 ]]; then
	cat "${RSYNC_LOG}" || reportError "${LINENO}" "${?}" "Listing differences between sources (${RSYNC_SOURCES[*]}) and destinations (${AVAILABLE_DESTINATION_ROOT_DIRS[*]}) started on ${START_TS} failed: cannot display ${RSYNC_LOG} contents!"
elif [[ ! -f "${RSYNC_LOG}" || -s "${RSYNC_LOG}" ]]; then
	reportError "${LINENO}" "${?}" "Rsync of sources (${RSYNC_SOURCES[*]}) to destinations (${AVAILABLE_DESTINATION_ROOT_DIRS[*]}) started on ${START_TS} failed: error log not empty!"
fi

#
# Cleanup.
#
if [[ -e "${TMP_DIR}" ]]; then
	(rm -f "${TMP_LOG}" ; rm -f "${RSYNC_LOG}" ; rmdir "${TMP_DIR}") || reportError "${LINENO}" "${?}" "Cannot cleanup tmp dir ${TMP_DIR}."
fi

#
# Signal success.
#
echo "INFO: Finished successfully."

#
# Reset trap and exit.
#
trap - EXIT
exit 0
