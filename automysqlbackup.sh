#!/bin/bash
#
# MySQL Backup Script
# VER. 2.5.1 - http://sourceforge.net/projects/automysqlbackup/
# Copyright (c) 2002-2003 wipe_out@lycos.co.uk
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA
#
#=====================================================================
#=====================================================================
# Set the following variables to your system needs
# (Detailed instructions below variables)
#=====================================================================
#set -x
CONFIGFILE="/etc/automysqlbackup/automysqlbackup.conf"

if [ -r ${CONFIGFILE} ]; then
    # Read the configfile if it's existing and readable
    source ${CONFIGFILE}
else
# do inline-config otherwise
# To create a configfile just copy the code between "### START CFG ###" and "### END CFG ###"
# to /etc/automysqlbackup/automysqlbackup.conf. After that you're able to upgrade this script
# (copy a new version to its location) without the need for editing it.

### START CFG ###
# Username to access the MySQL server e.g. dbuser
USERNAME=debian
# Password to access the MySQL server e.g. password
PASSWORD=
# Host name (or IP address) of MySQL server e.g localhost
DBHOST=localhost
# List of DBNAMES for Daily/Weekly Backup e.g. "DB1 DB2 DB3"
DBNAMES="all"
# Backup directory location e.g /backups
BACKUPDIR="/srv/backup/db"
# Mail setup
# What would you like to be mailed to you?
# - log   : send only log file
# - files : send log file and sql files as attachments (see docs)
# - stdout : will simply output the log to the screen if run manually.
# - quiet : Only send logs if an error occurs to the MAILADDR.
MAILCONTENT="log"
# Set the maximum allowed email size in k. (4000 = approx 5MB email [see docs])
MAXATTSIZE="4000"
# Email Address to send mail to? (user@domain.com)
MAILADDR="maintenance@example.com"
# ============================================================
# === ADVANCED OPTIONS ( Read the doc's for details )===
#=============================================================
# List of DBBNAMES for Monthly Backups.
MDBNAMES="${DBNAMES}"
# List of DBNAMES to EXLUCDE if DBNAMES are set to all (must be in " quotes)
DBEXCLUDE=""
# Include CREATE DATABASE in backup?
CREATE_DATABASE=no
# Separate backup directory and file for each DB? (yes or no)
SEPDIR=yes
# Which day do you want weekly backups? (1 to 7 where 1 is Monday)
DOWEEKLY=6
# Choose Compression type. (gzip or bzip2)
COMP=gzip
# Compress communications between backup server and MySQL server?
COMMCOMP=no
# Additionally keep a copy of the most recent backup in a seperate directory.
LATEST=no
#  The maximum size of the buffer for client/server communication. e.g. 16MB (maximum is 1GB)
MAX_ALLOWED_PACKET=
#  For connections to localhost. Sometimes the Unix socket file must be specified.
SOCKET=
# Command to run before backups (uncomment to use)
#PREBACKUP="/etc/mysql-backup-pre"
# Command run after backups (uncomment to use)
#POSTBACKUP="/etc/mysql-backup-post"
### END CFG ###
fi
#=====================================================================
#=====================================================================
#=====================================================================
#
# Should not need to be modified from here down!!
#
#=====================================================================
#=====================================================================
#=====================================================================
#
# Full pathname to binaries to avoid problems with aliases and builtins etc.
#
WHICH="`which which`"
AWK="`${WHICH} gawk`"
LOGGER="`${WHICH} logger`"
ECHO="`${WHICH} echo`"
CAT="`${WHICH} cat`"
BASENAME="`${WHICH} basename`"
DATEC="`${WHICH} date`"
DU="`${WHICH} du`"
EXPR="`${WHICH} expr`"
FIND="`${WHICH} find`"
RM="`${WHICH} rm`"
MYSQL="`${WHICH} mysql`"
MYSQLDUMP="`${WHICH} mysqldump`"
GZIP="`${WHICH} gzip`"
BZIP2="`${WHICH} bzip2`"
CP="`${WHICH} cp`"
HOSTNAMEC="`${WHICH} hostname`"
SED="`${WHICH} sed`"
GREP="`${WHICH} grep`"

#
function get_debian_pw() {
    if [ -r /etc/mysql/debian.cnf ]; then
        eval $(${AWK} '
            ! user && /^[[:space:]]*user[[:space:]]*=[[:space:]]*/ {
                print "USERNAME=" gensub(/.+[[:space:]]+([^[:space:]]+)[[:space:]]*$/, "\\1", "1"); user++
            }
            ! pass && /^[[:space:]]*password[[:space:]]*=[[:space:]]*/ {
                print "PASSWORD=" gensub(/.+[[:space:]]+([^[:space:]]+)[[:space:]]*$/, "\\1", "1"); pass++
            }' /etc/mysql/debian.cnf
        )
    else
        ${LOGGER} "${PROGNAME}: File \"/etc/mysql/debian.cnf\" not found."
        exit 1
    fi
}

[ "x${USERNAME}" = "xdebian" -a "x${PASSWORD}" = "x" ] && get_debian_pw

while [ $# -gt 0 ]; do
    case $1 in
        -c)
            if [ -r "$2" ]; then
                source "$2"
                shift 2
            else
                ${ECHO} "Ureadable config file \"$2\""
                exit 1
            fi
            ;;
        *)
            ${ECHO} "Unknown Option \"$1\""
            exit 2
            ;;
        esac
done

export LC_ALL=C
PROGNAME=`${BASENAME} $0`
PATH=/usr/local/bin:/usr/bin:/bin:/usr/local/mysql/bin
DATE=`${DATEC} +%Y-%m-%d_%Hh%Mm`				# Datestamp e.g 2002-09-21
DOW=`${DATEC} +%A`							# Day of the week e.g. Monday
DNOW=`${DATEC} +%u`						# Day number of the week 1 to 7 where 1 represents Monday
DOM=`${DATEC} +%d`							# Date of the Month e.g. 27
M=`${DATEC} +%B`							# Month e.g January
W=`${DATEC} +%V`							# Week Number e.g 37
VER=2.5.1									# Version Number
LOGFILE=${BACKUPDIR}/${DBHOST}-`${DATEC} +%N`.log		# Logfile Name
LOGERR=${BACKUPDIR}/ERRORS_${DBHOST}-`${DATEC} +%N`.log		# Logfile Name
BACKUPFILES=""
OPT="--quote-names --opt"			# OPT string for use with mysqldump ( see man mysqldump )

# IO redirection for logging.
touch ${LOGFILE}
exec 6>&1           # Link file descriptor #6 with stdout.
                    # Saves stdout.
exec > ${LOGFILE}     # stdout replaced with file ${LOGFILE}.
touch ${LOGERR}
exec 7>&2           # Link file descriptor #7 with stderr.
                    # Saves stderr.
exec 2> ${LOGERR}     # stderr replaced with file ${LOGERR}.

# Add --compress mysqldump option to ${OPT}
if [ "${COMMCOMP}" = "yes" ];
    then
        OPT="${OPT} --compress"
    fi

# Add --max_allowed_packet=... mysqldump option to ${OPT}
if [ "${MAX_ALLOWED_PACKET}" ];
    then
        OPT="${OPT} --max_allowed_packet=${MAX_ALLOWED_PACKET}"
    fi

# Create required directories
if [ ! -e "${BACKUPDIR}" ]		# Check Backup Directory exists.
    then
    mkdir -p "${BACKUPDIR}"
fi

if [ ! -e "${BACKUPDIR}/daily" ]		# Check Daily Directory exists.
    then
    mkdir -p "${BACKUPDIR}/daily"
fi

if [ ! -e "${BACKUPDIR}/weekly" ]		# Check Weekly Directory exists.
    then
    mkdir -p "${BACKUPDIR}/weekly"
fi

if [ ! -e "${BACKUPDIR}/monthly" ]	# Check Monthly Directory exists.
    then
    mkdir -p "${BACKUPDIR}/monthly"
fi

if [ "${LATEST}" = "yes" ]
then
    if [ ! -e "${BACKUPDIR}/latest" ]	# Check Latest Directory exists.
    then
        mkdir -p "${BACKUPDIR}/latest"
   fi
eval ${RM} -fv "${BACKUPDIR}/latest/*"
fi


# Functions

# Database dump function
dbdump () {
${MYSQLDUMP} --user=${USERNAME} --password=${PASSWORD} --host=${DBHOST} ${OPT} ${1} > ${2}
return $?
}

# Compression function plus latest copy
SUFFIX=""
compression () {
if [ "${COMP}" = "gzip" ]; then
    ${GZIP} -f "${1}"
    ${ECHO}
    ${ECHO} Backup Information for "${1}"
    ${GZIP} -l "${1}.gz"
    SUFFIX=".gz"
elif [ "${COMP}" = "bzip2" ]; then
    ${ECHO} Compression information for "${1}.bz2"
    ${BZIP2} -f -v ${1} 2>&1
    SUFFIX=".bz2"
else
    ${ECHO} "No compression option set, check advanced settings"
fi
if [ "${LATEST}" = "yes" ]; then
    ${CP} ${1}${SUFFIX} "${BACKUPDIR}/latest/"
fi
return 0
}


# Run command before we begin
if [ "${PREBACKUP}" ]
    then
        ${ECHO} ======================================================================
        ${ECHO} "Prebackup command output."
        ${ECHO}
        eval ${PREBACKUP}
        ${ECHO}
        ${ECHO} ======================================================================
        ${ECHO}
fi


if [ "${SEPDIR}" = "yes" ]; then # Check if CREATE DATABSE should be included in Dump
    if [ "${CREATE_DATABASE}" = "no" ]; then
        OPT="${OPT} --no-create-db"
    else
        OPT="${OPT} --databases"
    fi
else
    OPT="${OPT} --databases"
fi

# Hostname for LOG information
if [ "${DBHOST}" = "localhost" ]; then
    HOST=`${HOSTNAMEC}`
    if [ "${SOCKET}" ]; then
        OPT="${OPT} --socket=${SOCKET}"
    fi
else
    HOST=${DBHOST}
fi

# If backing up all DBs on the server
if [ "${DBNAMES}" = "all" ]; then
    DBNAMES="`${MYSQL} --user=${USERNAME} --password=${PASSWORD} --host=${DBHOST} --batch --skip-column-names -e "show databases"| ${SED} 's/ /%/g'`"

    # If DBs are excluded
    for exclude in ${DBEXCLUDE}
    do
        DBNAMES=`${ECHO} ${DBNAMES} | ${SED} "s/\b${exclude}\b//g"`
    done

    MDBNAMES=${DBNAMES}
fi

${ECHO} ======================================================================
${ECHO} AutoMySQLBackup VER ${VER}
${ECHO} http://sourceforge.net/projects/automysqlbackup/
${ECHO}
${ECHO} Backup of Database Server - ${HOST}
${ECHO} ======================================================================

# Test is seperate DB backups are required
if [ "${SEPDIR}" = "yes" ]; then
${ECHO} Backup Start Time `${DATEC}`
${ECHO} ======================================================================
    # Monthly Full Backup of all Databases
    if [ ${DOM} = "01" ]; then
        for MDB in ${MDBNAMES}
        do
            # Prepare ${DB} for using
                MDB="`${ECHO} ${MDB} | ${SED} 's/%/ /g'`"
                if [ ! -e "${BACKUPDIR}/monthly/${MDB}" ]		# Check Monthly DB Directory exists.
                then
                    mkdir -p "${BACKUPDIR}/monthly/${MDB}"
                fi
                ${ECHO} Monthly Backup of ${MDB}...
                dbdump "${MDB}" "${BACKUPDIR}/monthly/${MDB}/${MDB}_${DATE}.${M}.${MDB}.sql"
                [ $? -eq 0 ] && {
                    ${ECHO} "Rotating 5 month backups for ${MDB}"
                    ${FIND} "${BACKUPDIR}/monthly/${MDB}" -mtime +150 -type f -exec ${RM} -v {} \;
                }
                compression "${BACKUPDIR}/monthly/${MDB}/${MDB}_${DATE}.${M}.${MDB}.sql"
                BACKUPFILES="${BACKUPFILES} ${BACKUPDIR}/monthly/${MDB}/${MDB}_${DATE}.${M}.${MDB}.sql${SUFFIX}"
                ${ECHO} ----------------------------------------------------------------------
            done
    fi

    for DB in ${DBNAMES}
    do
        # Prepare ${DB} for using
        DB="`${ECHO} ${DB} | ${SED} 's/%/ /g'`"

    # Create Seperate directory for each DB
    if [ ! -e "${BACKUPDIR}/daily/${DB}" ]		# Check Daily DB Directory exists.
    then
        mkdir -p "${BACKUPDIR}/daily/${DB}"
    fi

    if [ ! -e "${BACKUPDIR}/weekly/${DB}" ]		# Check Weekly DB Directory exists.
    then
        mkdir -p "${BACKUPDIR}/weekly/${DB}"
    fi

# Weekly Backup
    if [ ${DNOW} = ${DOWEEKLY} ]; then
        ${ECHO} Weekly Backup of Database \( ${DB} \)
        ${ECHO}
            dbdump "${DB}" "${BACKUPDIR}/weekly/${DB}/${DB}_week.${W}.${DATE}.sql"
        [ $? -eq 0 ] && {
            ${ECHO} Rotating 5 weeks Backups...
            ${FIND} "${BACKUPDIR}/weekly/${DB}" -mtime +35 -type f -exec ${RM} -v {} \;
        }
        compression "${BACKUPDIR}/weekly/${DB}/${DB}_week.${W}.${DATE}.sql"
        BACKUPFILES="${BACKUPFILES} ${BACKUPDIR}/weekly/${DB}/${DB}_week.${W}.${DATE}.sql${SUFFIX}"
    ${ECHO} ----------------------------------------------------------------------

# Daily Backup
    else
        ${ECHO} Daily Backup of Database \( ${DB} \)
        ${ECHO}
            dbdump "${DB}" "${BACKUPDIR}/daily/${DB}/${DB}_${DATE}.${DOW}.sql"
            [ $? -eq 0 ] && {
                ${ECHO} Rotating last weeks Backup...
                ${FIND} "${BACKUPDIR}/daily/${DB}" -mtime +6 -type f -exec ${RM} -v {} \;
            }
            compression "${BACKUPDIR}/daily/${DB}/${DB}_${DATE}.${DOW}.sql"
            BACKUPFILES="${BACKUPFILES} ${BACKUPDIR}/daily/${DB}/${DB}_${DATE}.${DOW}.sql${SUFFIX}"
        ${ECHO} ----------------------------------------------------------------------
    fi
done

${ECHO} Backup End `${DATEC}`
${ECHO} ======================================================================


else # One backup file for all DBs
${ECHO} Backup Start `${DATEC}`
${ECHO} ======================================================================
    # Monthly Full Backup of all Databases
    if [ ${DOM} = "01" ]; then
        ${ECHO} Monthly full Backup of \( ${MDBNAMES} \)...
            dbdump "${MDBNAMES}" "${BACKUPDIR}/monthly/${DATE}.${M}.all-databases.sql"
            [ $? -eq 0 ] && {
                ${ECHO} "Rotating 5 month backups."
                ${FIND} "${BACKUPDIR}/monthly" -mtime +150 -type f -exec ${RM} -v {} \;
            }
            compression "${BACKUPDIR}/monthly/${DATE}.${M}.all-databases.sql"
            BACKUPFILES="${BACKUPFILES} ${BACKUPDIR}/monthly/${DATE}.${M}.all-databases.sql${SUFFIX}"
            ${ECHO} ----------------------------------------------------------------------
    fi

    # Weekly Backup
    if [ ${DNOW} = ${DOWEEKLY} ]; then
        ${ECHO} Weekly Backup of Databases \( ${DBNAMES} \)
        ${ECHO}
        ${ECHO}
            dbdump "${DBNAMES}" "${BACKUPDIR}/weekly/week.${W}.${DATE}.sql"
            [ $? -eq 0 ] && {
                ${ECHO} Rotating 5 weeks Backups...
                ${FIND} "${BACKUPDIR}/weekly/" -mtime +35 -type f -exec ${RM} -v {} \;
            }
            compression "${BACKUPDIR}/weekly/week.${W}.${DATE}.sql"
            BACKUPFILES="${BACKUPFILES} ${BACKUPDIR}/weekly/week.${W}.${DATE}.sql${SUFFIX}"
        ${ECHO} ----------------------------------------------------------------------

    # Daily Backup
    else
        ${ECHO} Daily Backup of Databases \( ${DBNAMES} \)
        ${ECHO}
        ${ECHO}
            dbdump "${DBNAMES}" "${BACKUPDIR}/daily/${DATE}.${DOW}.sql"
            [ $? -eq 0 ] && {
                ${ECHO} Rotating last weeks Backup...
                ${FIND} "${BACKUPDIR}/daily" -mtime +6 -type f -exec ${RM} -v {} \;
            }
            compression "${BACKUPDIR}/daily/${DATE}.${DOW}.sql"
            BACKUPFILES="${BACKUPFILES} ${BACKUPDIR}/daily/${DATE}.${DOW}.sql${SUFFIX}"
            ${ECHO} ----------------------------------------------------------------------
    fi
${ECHO} Backup End Time `${DATEC}`
${ECHO} ======================================================================
fi
${ECHO} Total disk space used for backup storage..
${ECHO} Size - Location
${ECHO} `${DU} -hs "${BACKUPDIR}"`
${ECHO}
${ECHO} ======================================================================
${ECHO} If you find AutoMySQLBackup valuable please make a donation at
${ECHO} http://sourceforge.net/project/project_donations.php?group_id=101066
${ECHO} ======================================================================

# Run command when we're done
if [ "${POSTBACKUP}" ]
    then
    ${ECHO} ======================================================================
    ${ECHO} "Postbackup command output."
    ${ECHO}
    eval ${POSTBACKUP}
    ${ECHO}
    ${ECHO} ======================================================================
fi

#Clean up IO redirection
exec 1>&6 6>&-      # Restore stdout and close file descriptor #6.
exec 2>&7 7>&-      # Restore stdout and close file descriptor #7.

if [ "${MAILCONTENT}" = "files" ]
then
    if [ -s "${LOGERR}" ]
    then
        # Include error log if is larger than zero.
        BACKUPFILES="${BACKUPFILES} ${LOGERR}"
        ERRORNOTE="WARNING: Error Reported - "
    fi
    #Get backup size
    ATTSIZE=`${DU} -c ${BACKUPFILES} | ${GREP} "[[:digit:][:space:]]total$" |${SED} s/\s*total//`
    if [ ${MAXATTSIZE} -ge ${ATTSIZE} ]
    then
        BACKUPFILES=`${ECHO} "${BACKUPFILES}" | ${SED} -e "s# # -a #g"`	#enable multiple attachments
        mutt -s "${ERRORNOTE} MySQL Backup Log and SQL Files for ${HOST} - ${DATE}" ${BACKUPFILES} ${MAILADDR} < ${LOGFILE}		#send via mutt
    else
        ${CAT} "${LOGFILE}" | mail -s "WARNING! - MySQL Backup exceeds set maximum attachment size on ${HOST} - ${DATE}" ${MAILADDR}
    fi
elif [ "${MAILCONTENT}" = "log" ]
then
    ${CAT} "${LOGFILE}" | mail -s "MySQL Backup Log for ${HOST} - ${DATE}" ${MAILADDR}
    if [ -s "${LOGERR}" ]
        then
            ${CAT} "${LOGERR}" | mail -s "ERRORS REPORTED: MySQL Backup error Log for ${HOST} - ${DATE}" ${MAILADDR}
    fi
elif [ "${MAILCONTENT}" = "quiet" ]
then
    if [ -s "${LOGERR}" ]
        then
            ${CAT} "${LOGERR}" | mail -s "ERRORS REPORTED: MySQL Backup error Log for ${HOST} - ${DATE}" ${MAILADDR}
            ${CAT} "${LOGFILE}" | mail -s "MySQL Backup Log for ${HOST} - ${DATE}" ${MAILADDR}
        fi
else
    if [ -s "${LOGERR}" ]
        then
            ${CAT} "${LOGFILE}"
            ${ECHO}
            ${ECHO} "###### WARNING ######"
            ${ECHO} "Errors reported during AutoMySQLBackup execution.. Backup failed"
            ${ECHO} "Error log below.."
            ${CAT} "${LOGERR}"
        else
            ${CAT} "${LOGFILE}"
    fi
fi

if [ -s "${LOGERR}" ]
    then
        STATUS=1
    else
        STATUS=0
fi

# Clean up Logfile
eval ${RM} -f "${LOGFILE}"
eval ${RM} -f "${LOGERR}"

exit ${STATUS}
